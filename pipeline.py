"""ML pipeline: parse a FitNotes CSV export and train a per-user XGBoost model."""

import re

import numpy as np
import pandas as pd
import xgboost as xgb


def calculate_hybrid_1rm(weight: float, reps: int) -> float:
    """Estimate 1RM using a formula matched to the rep range.

    - Brzycki  for 1–6 reps (accurate at low rep counts)
    - Epley    for 7–11 reps
    - Mayhew   for 12+ reps (better fit for high-rep endurance sets)
    """
    if reps <= 0:
        return 0
    if reps <= 6:
        return weight / (1.0278 - 0.0278 * reps)
    if reps <= 11:
        return weight * (1 + 0.0333 * reps)
    return (100 * weight) / (52.2 + 41.9 * np.exp(-0.055 * reps))


_FORM_ISSUE_RE = re.compile(
    r"did it wrong|wrong|unsure|too heavy|failed|couldn't"
    r"|can't complete|sloppy|lost balance|form is\s*(off|weird|bad)"
    r"|feeling tricep|feeling arm|injury",
    re.IGNORECASE,
)
_FATIGUE_RE = re.compile(
    r"forearm|fatigued|tired|gave out"
    r"|grip\s*(loose|gave|gone|tiring)|arms gave|tiring out|limiting",
    re.IGNORECASE,
)
_DROP_SET_RE = re.compile(r"drop\s*set|no rest", re.IGNORECASE)
_WARMUP_RE = re.compile(r"warm[\s-]?up", re.IGNORECASE)

STRENGTH_CATEGORIES = {
    "Chest", "Back", "Legs", "Shoulders", "Biceps", "Triceps", "Arms", "Abs"
}


def _tag_comment(comment) -> tuple:
    """Return ``(form_issue, fatigue, is_drop_set, is_warmup)`` for one comment."""
    if pd.isna(comment) or not str(comment).strip():
        return 0, 0, False, False
    return (
        int(bool(_FORM_ISSUE_RE.search(comment))),
        int(bool(_FATIGUE_RE.search(comment))),
        bool(_DROP_SET_RE.search(comment)),
        bool(_WARMUP_RE.search(comment)),
    )


def _rolling_slope(series: pd.Series) -> pd.Series:
    """Linear slope of 1RM over a 3-session window; 0 for the first two sessions."""
    vals = series.values
    result = np.zeros(len(vals))
    for i in range(2, len(vals)):
        result[i] = np.polyfit([0, 1, 2], vals[i - 2:i + 1], 1)[0]
    return pd.Series(result, index=series.index)


def run_pipeline(uploaded_file) -> tuple:
    """Parse *uploaded_file*, engineer features, and train an XGBoost regressor.

    Returns ``(model, feature_cols, summary)`` where *summary* is the
    session-level aggregation used for inference in the API.
    """
    print("Starting pipeline...")

    df = pd.read_csv(uploaded_file)
    df.columns = df.columns.str.strip()

    df = df[df["Category"].isin(STRENGTH_CATEGORIES)].copy()

    # Coerce before dropna so non-numeric strings are treated as missing
    # rather than causing downstream arithmetic errors.
    df["Weight"] = pd.to_numeric(df["Weight"], errors="coerce")
    df["Reps"] = pd.to_numeric(df["Reps"], errors="coerce")
    df = df.dropna(subset=["Weight", "Reps"]).copy()
    df["Date"] = pd.to_datetime(df["Date"])

    tags = df["Comment"].apply(_tag_comment)
    df[["Form_Issue", "Fatigue_Flag", "Is_Drop_Set", "Is_Warmup"]] = (
        pd.DataFrame(tags.tolist(), index=df.index)
    )

    # Exclude drop sets — they inflate volume without reflecting max capacity.
    # Exclude tagged warm-ups for the same reason.
    working = df[~df["Is_Drop_Set"] & ~df["Is_Warmup"]].copy()

    # Also filter weight-based warm-ups: sets < 60 % of that session's max weight.
    session_max_w = working.groupby(["Date", "Exercise"])["Weight"].transform("max")
    working = working[working["Weight"] >= 0.6 * session_max_w].copy()

    working["Estimated_1RM"] = working.apply(
        lambda r: calculate_hybrid_1rm(r["Weight"], int(r["Reps"])), axis=1
    )

    def _rep_consistency(x):
        return float(x.min() / x.mean()) if x.mean() > 0 else 1.0

    summary = working.groupby(["Date", "Exercise", "Category"]).agg(
        Sets=("Reps", "count"),
        Avg_Reps=("Reps", "mean"),
        Max_Weight=("Weight", "max"),
        Session_Max_1RM=("Estimated_1RM", "max"),
        Had_Form_Issue=("Form_Issue", "max"),
        Had_Fatigue=("Fatigue_Flag", "max"),
        Rep_Consistency=("Reps", _rep_consistency),
    ).reset_index()

    summary["Volume_Load"] = (
        summary["Sets"] * summary["Avg_Reps"] * summary["Max_Weight"]
    )
    summary = summary.sort_values(["Exercise", "Date"]).reset_index(drop=True)

    g = summary.groupby("Exercise")
    summary["Days_Since_Last"] = g["Date"].diff().dt.days.fillna(14)
    summary["Previous_1RM"] = (
        g["Session_Max_1RM"].shift().fillna(summary["Session_Max_1RM"])
    )
    summary["Last_Avg_Reps"] = (
        g["Avg_Reps"].shift().fillna(summary["Avg_Reps"])
    )
    summary["Prev_Volume_Load"] = (
        g["Volume_Load"].shift().fillna(summary["Volume_Load"])
    )
    summary["Prev_Form_Issue"] = (
        g["Had_Form_Issue"].shift().fillna(0).astype(int)
    )
    summary["Prev_Fatigue"] = (
        g["Had_Fatigue"].shift().fillna(0).astype(int)
    )
    summary["Prev_Rep_Consistency"] = (
        g["Rep_Consistency"].shift().fillna(1.0)
    )

    # Positive = improving trend, negative = declining.
    summary["RM_Momentum"] = (
        summary.groupby("Exercise")["Session_Max_1RM"].transform(_rolling_slope)
    )

    # Build feature matrix using only information available before the next workout.
    encoded = pd.get_dummies(summary, columns=["Exercise", "Category"])
    to_drop = [
        "Date", "Max_Weight", "Session_Max_1RM",
        "Sets", "Avg_Reps", "Volume_Load",
        "Had_Form_Issue", "Had_Fatigue", "Rep_Consistency",
    ]
    X = encoded.drop(columns=to_drop, errors="ignore")
    y = encoded["Session_Max_1RM"]

    print(f"Training XGBoost on {len(X)} rows, {len(X.columns)} features...")
    model = xgb.XGBRegressor(
        n_estimators=200,
        learning_rate=0.05,
        max_depth=4,
        subsample=0.8,
        colsample_bytree=0.8,
        min_child_weight=3,
        random_state=42,
    )
    model.fit(X, y)

    print("Pipeline complete.")
    return model, list(X.columns), summary

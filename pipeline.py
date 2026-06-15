"""ML pipeline: parse a FitNotes CSV export and train a per-user XGBoost model."""

import re

import numpy as np
import pandas as pd
import xgboost as xgb


def calculate_hybrid_1rm(weight: float, reps: int) -> float:
    """Estimate 1RM using the formula that's most accurate for the rep range.

    The relationship between reps-to-failure and 1RM is non-linear, so a
    single formula performs poorly across all rep ranges. Three formulas
    are blended by range:

    - Brzycki  (1–6 reps): derived from powerlifting data; accurate for
      heavy, low-rep work where percentage-of-1RM is high.
    - Epley    (7–11 reps): general-purpose formula; good mid-range fit.
    - Mayhew   (12+ reps): exponential decay prevents wild extrapolation
      when reps approach muscular endurance territory.
    """
    if reps <= 0:
        return 0
    if reps <= 6:
        # CAUTION: denominator (1.0278 - 0.0278 * reps) reaches zero at ~37 reps,
        # but this branch only runs for reps 1–6 so division-by-zero is impossible.
        return weight / (1.0278 - 0.0278 * reps)
    if reps <= 11:
        return weight * (1 + 0.0333 * reps)
    # Mayhew: as reps → ∞, the exponential term vanishes and the formula
    # plateaus near (100 * weight) / 52.2, acting as a natural upper bound.
    return (100 * weight) / (52.2 + 41.9 * np.exp(-0.055 * reps))


# Compiled once at module level — these patterns run across every row in the
# CSV, so avoiding re-compilation per row matters on large datasets.
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

# Only weight-and-reps categories produce valid 1RM estimates.
# Cardio uses distance/duration; Passive logs recovery — both are excluded.
STRENGTH_CATEGORIES = {
    # FitNotes export names
    "Chest",
    "Back",
    "Legs",
    "Shoulders",
    "Biceps",
    "Triceps",
    "Arms",
    "Abs",
    # In-app manual-entry names (differ from FitNotes)
    "Core",
    "Forearms",
}


def _tag_comment(comment) -> tuple:
    """Classify a free-text set note into four binary flags.

    Returns (form_issue, fatigue, is_drop_set, is_warmup) as (int, int, bool, bool).
    pd.NA, None, NaN, and blank strings are treated identically as "no comment."
    """
    # pd.isna handles None, float('nan'), and pd.NA in one check.
    if pd.isna(comment) or not str(comment).strip():
        return 0, 0, False, False
    return (
        int(bool(_FORM_ISSUE_RE.search(comment))),
        int(bool(_FATIGUE_RE.search(comment))),
        bool(_DROP_SET_RE.search(comment)),
        bool(_WARMUP_RE.search(comment)),
    )


def _rolling_slope(series: pd.Series) -> pd.Series:
    """Return the linear slope of 1RM values over a sliding 3-session window.

    A 3-session window balances noise suppression against responsiveness:
    single-session variance is high (bad sleep, stress, nutrition can drop
    1RM by 5–10%), but wider windows lag too far behind genuine trends.
    The first two positions always return 0 because the window isn't full yet.
    """
    values = series.values
    slopes = np.zeros(len(values))
    for i in range(2, len(values)):
        # polyfit([0,1,2], ...) treats sessions as evenly spaced integers.
        # Index 0 of the result is the slope coefficient.
        slopes[i] = np.polyfit([0, 1, 2], values[i - 2 : i + 1], 1)[0]
    return pd.Series(slopes, index=series.index)


def run_pipeline(uploaded_file) -> tuple:
    """Parse a FitNotes CSV, engineer lag features, and train an XGBoost regressor.

    Returns (model, feature_cols, session_summary) where session_summary holds
    the per-session aggregates used at inference time by the API.

    Raises ValueError for:
    - Missing required CSV columns
    - Fewer than 10 valid strength sets after category filtering
    - No working sets remaining after drop-set and warm-up exclusion
    """
    print("Starting pipeline...")

    df = pd.read_csv(uploaded_file)
    # FitNotes sometimes pads header names with trailing spaces.
    df.columns = df.columns.str.strip()

    required_columns = {"Date", "Exercise", "Category", "Weight", "Reps"}
    missing_columns = required_columns - set(df.columns)
    if missing_columns:
        raise ValueError(
            f"CSV is missing required columns: {', '.join(sorted(missing_columns))}. "
            "Export your data from FitNotes and try again."
        )

    # Keep only strength exercises — Cardio/Passive data can't produce a 1RM estimate.
    df = df[df["Category"].isin(STRENGTH_CATEGORIES)].copy()

    # errors="coerce" turns non-numeric strings (e.g. "N/A", "--") into NaN
    # so they're cleanly dropped by dropna rather than crashing later arithmetic.
    df["Weight"] = pd.to_numeric(df["Weight"], errors="coerce")
    df["Reps"] = pd.to_numeric(df["Reps"], errors="coerce")
    df = df.dropna(subset=["Weight", "Reps"]).copy()
    df["Date"] = pd.to_datetime(df["Date"])

    if len(df) < 10:
        raise ValueError(
            f"Not enough training data: {len(df)} valid strength set(s) found. "
            "Log at least 10 sets across multiple sessions before retraining."
        )

    comment_tags = df["Comment"].apply(_tag_comment)
    df[["Form_Issue", "Fatigue_Flag", "Is_Drop_Set", "Is_Warmup"]] = pd.DataFrame(
        comment_tags.tolist(), index=df.index
    )

    # Drop sets use a lower weight-to-failure than a true working set, so
    # including them inflates volume and underestimates 1RM capacity.
    # Tagged warm-ups are excluded for the same reason.
    working_sets = df[~df["Is_Drop_Set"] & ~df["Is_Warmup"]].copy()

    # Secondary warm-up filter: even without a comment, any set below 60% of
    # the session's peak weight is almost certainly a feeler or warm-up set.
    if not working_sets.empty:
        session_peak_weight = working_sets.groupby(["Date", "Exercise"])["Weight"].transform("max")
        working_sets = working_sets[working_sets["Weight"] >= 0.6 * session_peak_weight].copy()

    if working_sets.empty:
        raise ValueError(
            "No valid working sets found after excluding drop sets and warm-ups. "
            "Ensure your CSV contains at least some regular strength sets."
        )

    working_sets["Estimated_1RM"] = working_sets.apply(
        lambda row: calculate_hybrid_1rm(row["Weight"], int(row["Reps"])), axis=1
    )

    def _rep_consistency_ratio(rep_counts):
        # min/mean ratio: 1.0 = all sets had the same reps (very consistent);
        # values closer to 0 indicate a big drop-off across sets (fatiguing fast).
        return float(rep_counts.min() / rep_counts.mean()) if rep_counts.mean() > 0 else 1.0

    # Collapse individual sets into one row per (Date, Exercise) training session.
    session_summary = (
        working_sets.groupby(["Date", "Exercise", "Category"])
        .agg(
            Sets=("Reps", "count"),
            Avg_Reps=("Reps", "mean"),
            Max_Weight=("Weight", "max"),
            Session_Max_1RM=("Estimated_1RM", "max"),
            Had_Form_Issue=("Form_Issue", "max"),
            Had_Fatigue=("Fatigue_Flag", "max"),
            Rep_Consistency=("Reps", _rep_consistency_ratio),
        )
        .reset_index()
    )

    session_summary["Volume_Load"] = (
        session_summary["Sets"] * session_summary["Avg_Reps"] * session_summary["Max_Weight"]
    )
    session_summary = session_summary.sort_values(["Exercise", "Date"]).reset_index(drop=True)

    # Lag features give the model visibility into the previous session.
    # What happened last time is the strongest single predictor of next-session
    # performance — hence Previous_1RM and Days_Since_Last are the most important features.
    by_exercise = session_summary.groupby("Exercise")
    # Fill the very first session's Days_Since_Last with 14 (a typical weekly cadence).
    session_summary["Days_Since_Last"] = by_exercise["Date"].diff().dt.days.fillna(14)
    session_summary["Previous_1RM"] = (
        by_exercise["Session_Max_1RM"].shift().fillna(session_summary["Session_Max_1RM"])
    )
    session_summary["Last_Avg_Reps"] = (
        by_exercise["Avg_Reps"].shift().fillna(session_summary["Avg_Reps"])
    )
    session_summary["Prev_Volume_Load"] = (
        by_exercise["Volume_Load"].shift().fillna(session_summary["Volume_Load"])
    )
    session_summary["Prev_Form_Issue"] = by_exercise["Had_Form_Issue"].shift().fillna(0).astype(int)
    session_summary["Prev_Fatigue"] = by_exercise["Had_Fatigue"].shift().fillna(0).astype(int)
    session_summary["Prev_Rep_Consistency"] = by_exercise["Rep_Consistency"].shift().fillna(1.0)

    # Positive momentum = 1RM is trending upward; negative = declining capacity.
    session_summary["RM_Momentum"] = session_summary.groupby("Exercise")[
        "Session_Max_1RM"
    ].transform(_rolling_slope)

    # One-hot encode Exercise and Category so the model learns separate coefficients
    # per movement pattern — squat and bench press respond very differently.
    feature_matrix = pd.get_dummies(session_summary, columns=["Exercise", "Category"])

    # These columns are either the prediction target (Session_Max_1RM) or are
    # only measurable after the session ends. Including them as features would
    # leak future information into training and produce falsely optimistic accuracy.
    leaky_columns = [
        "Date",
        "Max_Weight",
        "Session_Max_1RM",
        "Sets",
        "Avg_Reps",
        "Volume_Load",
        "Had_Form_Issue",
        "Had_Fatigue",
        "Rep_Consistency",
    ]
    X = feature_matrix.drop(columns=leaky_columns, errors="ignore")
    y = feature_matrix["Session_Max_1RM"]

    print(f"Training XGBoost on {len(X)} rows, {len(X.columns)} features...")
    model = xgb.XGBRegressor(
        n_estimators=200,
        learning_rate=0.05,
        # max_depth=4 keeps trees shallow to avoid overfitting on small personal datasets
        # (most users have tens to hundreds of sessions, not thousands).
        max_depth=4,
        subsample=0.8,
        colsample_bytree=0.8,
        # min_child_weight=3 requires at least 3 samples per leaf, preventing the model
        # from memorising outlier sessions as if they were real signal.
        min_child_weight=3,
        random_state=42,
    )
    model.fit(X, y)

    print("Pipeline complete.")
    return model, list(X.columns), session_summary

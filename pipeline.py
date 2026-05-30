import re
import pandas as pd
import numpy as np
import xgboost as xgb
import joblib

# Hybrid 1RM formula — unchanged, well-grounded
def calculate_hybrid_1rm(weight, reps):
    if reps <= 0: return 0
    if reps <= 6:    return weight / (1.0278 - 0.0278 * reps)              # Brzycki
    elif reps <= 11: return weight * (1 + 0.0333 * reps)                   # Epley
    else:            return (100 * weight) / (52.2 + 41.9 * np.exp(-0.055 * reps))  # Mayhew

# Patterns derived from actual notes in the dataset
_FORM_ISSUE_RE = re.compile(
    r'did it wrong|wrong|unsure|too heavy|failed|couldn\'t|can\'t complete|sloppy|'
    r'lost balance|form is\s*(off|weird|bad)|feeling tricep|feeling arm|injury',
    re.IGNORECASE
)
_FATIGUE_RE = re.compile(
    r'forearm|fatigued|tired|gave out|grip\s*(loose|gave|gone|tiring)|'
    r'arms gave|tiring out|limiting',
    re.IGNORECASE
)
_DROP_SET_RE  = re.compile(r'drop\s*set|no rest', re.IGNORECASE)
_WARMUP_RE    = re.compile(r'warm[\s-]?up', re.IGNORECASE)

STRENGTH_CATEGORIES = {'Chest', 'Back', 'Legs', 'Shoulders', 'Biceps', 'Triceps', 'Arms', 'Abs'}


def _tag_comment(comment):
    """Return (form_issue, fatigue, is_drop_set, is_warmup) for a single comment."""
    if pd.isna(comment) or not str(comment).strip():
        return 0, 0, False, False
    return (
        int(bool(_FORM_ISSUE_RE.search(comment))),
        int(bool(_FATIGUE_RE.search(comment))),
        bool(_DROP_SET_RE.search(comment)),
        bool(_WARMUP_RE.search(comment)),
    )


def _rolling_slope(series):
    """Linear slope of 1RM over a 3-session window. 0 for first two sessions."""
    vals = series.values
    result = np.zeros(len(vals))
    for i in range(2, len(vals)):
        result[i] = np.polyfit([0, 1, 2], vals[i - 2:i + 1], 1)[0]
    return pd.Series(result, index=series.index)


def run_pipeline(uploaded_file):
    print("Starting pipeline...")

    df = pd.read_csv(uploaded_file)
    df.columns = df.columns.str.strip()

    # Only model strength exercises — cardio/passive have no weight+reps to learn from
    df = df[df['Category'].isin(STRENGTH_CATEGORIES)].copy()
    df = df.dropna(subset=['Weight', 'Reps']).copy()
    df['Date'] = pd.to_datetime(df['Date'])

    # Parse comment signals into columns
    tags = df['Comment'].apply(_tag_comment)
    df[['Form_Issue', 'Fatigue_Flag', 'Is_Drop_Set', 'Is_Warmup']] = pd.DataFrame(
        tags.tolist(), index=df.index
    )

    # Exclude drop sets — they inflate volume but don't represent max capacity
    # Exclude tagged warm-ups
    working = df[~df['Is_Drop_Set'] & ~df['Is_Warmup']].copy()

    # Also filter weight-based warm-ups: sets < 60% of that session's max weight
    session_max_w = working.groupby(['Date', 'Exercise'])['Weight'].transform('max')
    working = working[working['Weight'] >= 0.6 * session_max_w].copy()

    working['Estimated_1RM'] = working.apply(
        lambda r: calculate_hybrid_1rm(r['Weight'], r['Reps']), axis=1
    )

    # Aggregate to one row per session per exercise
    summary = working.groupby(['Date', 'Exercise', 'Category']).agg(
        Sets=('Reps', 'count'),
        Avg_Reps=('Reps', 'mean'),
        Max_Weight=('Weight', 'max'),
        Session_Max_1RM=('Estimated_1RM', 'max'),
        Had_Form_Issue=('Form_Issue', 'max'),
        Had_Fatigue=('Fatigue_Flag', 'max'),
        # How well did reps hold across sets? 1.0 = perfectly consistent, lower = dropped off
        Rep_Consistency=('Reps', lambda x: float(x.min() / x.mean()) if x.mean() > 0 else 1.0),
    ).reset_index()

    summary['Volume_Load'] = summary['Sets'] * summary['Avg_Reps'] * summary['Max_Weight']
    summary = summary.sort_values(['Exercise', 'Date']).reset_index(drop=True)

    g = summary.groupby('Exercise')
    summary['Days_Since_Last']       = g['Date'].diff().dt.days.fillna(14)
    summary['Previous_1RM']          = g['Session_Max_1RM'].shift().fillna(summary['Session_Max_1RM'])
    summary['Last_Avg_Reps']         = g['Avg_Reps'].shift().fillna(summary['Avg_Reps'])
    summary['Prev_Volume_Load']      = g['Volume_Load'].shift().fillna(summary['Volume_Load'])
    summary['Prev_Form_Issue']       = g['Had_Form_Issue'].shift().fillna(0).astype(int)
    summary['Prev_Fatigue']          = g['Had_Fatigue'].shift().fillna(0).astype(int)
    summary['Prev_Rep_Consistency']  = g['Rep_Consistency'].shift().fillna(1.0)

    # 1RM momentum: positive = improving trend, negative = declining
    summary['RM_Momentum'] = (
        summary.groupby('Exercise')['Session_Max_1RM'].transform(_rolling_slope)
    )

    # Build feature matrix — only include info available BEFORE the next workout
    encoded = pd.get_dummies(summary, columns=['Exercise', 'Category'])
    to_drop = [
        'Date', 'Max_Weight', 'Session_Max_1RM',   # target + raw identifiers
        'Sets', 'Avg_Reps', 'Volume_Load',           # current-session unknowns
        'Had_Form_Issue', 'Had_Fatigue', 'Rep_Consistency',
    ]
    X = encoded.drop(columns=to_drop, errors='ignore')
    y = encoded['Session_Max_1RM']

    print(f"Training XGBoost on {len(X)} rows, {len(X.columns)} features...")
    model = xgb.XGBRegressor(
        n_estimators=200,
        learning_rate=0.05,     # slower learning generalizes better on small datasets
        max_depth=4,            # shallower trees reduce memorization
        subsample=0.8,
        colsample_bytree=0.8,
        min_child_weight=3,
        random_state=42,
    )
    model.fit(X, y)

    joblib.dump(model, 'xgb_model.joblib')
    joblib.dump(list(X.columns), 'feature_cols.joblib')
    summary.to_csv('Processed_Workout_Data.csv', index=False)
    print("Pipeline complete.")
    return True

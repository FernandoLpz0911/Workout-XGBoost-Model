"""Workout ML — local FastAPI backend serving per-user XGBoost models.

Endpoints
---------
POST   /train             Retrain the user's XGBoost model from a CSV.
GET    /exercises         List exercises from the user's training history.
POST   /recommend         Return an AI weight/rep target for a given exercise.
DELETE /delete-user-data  Wipe all locally stored model data for the user.

Pass the user's local identifier in the ``X-User-ID`` header.
No cloud credentials or authentication tokens are required.
"""

import io
import os
import shutil
import threading
import time
from typing import Optional

import joblib
import numpy as np
import pandas as pd
from fastapi import (
    BackgroundTasks,
    Depends,
    FastAPI,
    File,
    Header,
    HTTPException,
    UploadFile,
)
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

from pipeline import run_pipeline

app = FastAPI(title="Workout ML API")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Local directory where per-user model artifacts are stored.
# Override with MODEL_DIR env var (e.g. for Docker volumes).
_MODEL_DIR = os.getenv("MODEL_DIR", "./models")

_MAX_CSV_BYTES = 50 * 1024 * 1024  # 50 MB hard cap on training uploads

# In-process FIFO model cache. dict preserves insertion order (Python 3.7+)
# so next(iter(...)) reliably returns the oldest entry for eviction.
_CACHE_MAX = 50
_model_cache: dict[str, tuple] = {}

# Thread-safe set tracking users whose training job is currently running.
# Prevents overlapping retrains that would corrupt on-disk model files.
_training_lock = threading.Lock()
_training_in_progress: set[str] = set()


def _model_dir(uid: str) -> str:
    return os.path.join(_MODEL_DIR, uid)


def _evict_model_cache() -> None:
    """Drop the oldest cache entry when the cache is at capacity."""
    if len(_model_cache) >= _CACHE_MAX:
        oldest_uid = next(iter(_model_cache))
        del _model_cache[oldest_uid]


def _claim_training_slot(uid: str) -> bool:
    """Atomically check and claim the training slot for this user.

    Returns True if the slot was free and is now claimed, False if a
    training job for this user is already running.
    """
    with _training_lock:
        if uid in _training_in_progress:
            return False
        _training_in_progress.add(uid)
        return True


def _release_training_slot(uid: str) -> None:
    with _training_lock:
        _training_in_progress.discard(uid)


def _save_user_model(
    uid: str, model, feature_cols: list, session_summary: pd.DataFrame
) -> None:
    """Persist model artifacts to disk and warm the in-process cache.

    Three files per user: the XGBoost model, the feature column list
    (needed to construct inference rows), and the session summary CSV
    (used to look up last-session stats at recommendation time).
    """
    path = _model_dir(uid)
    os.makedirs(path, exist_ok=True)
    joblib.dump(model, os.path.join(path, "xgb_model.joblib"))
    joblib.dump(feature_cols, os.path.join(path, "feature_cols.joblib"))
    session_summary.to_csv(os.path.join(path, "workout_summary.csv"), index=False)
    _evict_model_cache()
    _model_cache[uid] = (model, feature_cols, session_summary)


def _load_user_model(uid: str) -> tuple | None:
    """Return (model, feature_cols, session_summary) from cache or disk.

    Returns None if no model has been trained yet for this user.
    """
    if uid in _model_cache:
        return _model_cache[uid]

    path = _model_dir(uid)
    try:
        model = joblib.load(os.path.join(path, "xgb_model.joblib"))
        feature_cols = joblib.load(os.path.join(path, "feature_cols.joblib"))
        session_summary = pd.read_csv(
            os.path.join(path, "workout_summary.csv"),
            parse_dates=["Date"],
        )
        _evict_model_cache()
        _model_cache[uid] = (model, feature_cols, session_summary)
        return _model_cache[uid]
    except Exception:  # noqa: BLE001
        return None


def get_uid(x_user_id: Optional[str] = Header(None)) -> str:
    """FastAPI dependency — extract the user ID from the X-User-ID header.

    Raises 401 if the header is absent; all routes require a user identity.
    """
    if not x_user_id:
        raise HTTPException(401, "Missing X-User-ID header.")
    return x_user_id


def _run_train(uid: str, csv_bytes: bytes) -> None:
    """Run the ML pipeline and persist the result to disk.

    Runs as a FastAPI BackgroundTask so the HTTP response returns immediately.
    The training slot is always released when the job finishes.
    """
    try:
        model, feature_cols, session_summary = run_pipeline(io.BytesIO(csv_bytes))
        _save_user_model(uid, model, feature_cols, session_summary)
        print(f"Training complete for {uid}")
    except Exception as exc:  # noqa: BLE001
        print(f"Training error for {uid}: {exc}")
    finally:
        _release_training_slot(uid)


@app.post("/train")
async def train_model(
    background_tasks: BackgroundTasks,
    file: UploadFile = File(...),
    uid: str = Depends(get_uid),
):
    """Accept a CSV upload and queue a background model retrain.

    Returns immediately with 200; training runs asynchronously.
    Returns 409 if a training job is already running for this user.
    """
    if not file.filename.endswith(".csv"):
        raise HTTPException(400, "Only CSV files are allowed.")

    if not _claim_training_slot(uid):
        raise HTTPException(409, "Training already in progress for this account.")

    try:
        csv_bytes = await file.read()
    except Exception:
        _release_training_slot(uid)
        raise HTTPException(400, "Failed to read uploaded file.")

    if len(csv_bytes) > _MAX_CSV_BYTES:
        _release_training_slot(uid)
        raise HTTPException(
            413,
            f"File too large. Maximum size is {_MAX_CSV_BYTES // (1024 * 1024)} MB.",
        )

    background_tasks.add_task(_run_train, uid, csv_bytes)
    return {"message": "Training started."}


@app.get("/exercises")
def get_exercises(uid: str = Depends(get_uid)):
    """Return the user's exercise catalogue grouped by category."""
    assets = _load_user_model(uid)
    if assets is None:
        raise HTTPException(404, "No trained model. Upload CSV via /train.")
    _, _, session_summary = assets
    try:
        return (
            session_summary.groupby("Category")["Exercise"]
            .unique()
            .apply(list)
            .to_dict()
        )
    except Exception as exc:
        raise HTTPException(500, str(exc)) from exc


class WorkoutRequest(BaseModel):
    category: str
    exercise: str
    mode: str = "hypertrophy"  # "hypertrophy" | "strength"


def _epley_working_weight(one_rm: float, target_reps: int) -> float:
    """Convert a 1RM estimate to a working weight using the Epley formula.

    Epley (inverted): weight = 1RM / (1 + 0.0333 * reps).
    """
    return one_rm / (1 + 0.0333 * target_reps)


@app.post("/recommend")
def get_recommendation(req: WorkoutRequest, uid: str = Depends(get_uid)):
    """Return an AI-generated weight and rep target for the given exercise.

    Decision logic (in priority order):
    1. FORM FOCUS    — technique issues logged last session; repeat weight.
    2. DELOAD        — 4-session plateau detected; drop to 60% to reset fatigue.
    3. PROGRESSION   — hit graduation reps last session; bump weight.
    4. STABILIZATION — reps too low to safely progress; build rep count first.
    5. VOLUME        — in the working rep range; push toward graduation target.
    6. AI OVERRIDE   — XGBoost predicts capacity too low; scale weight down.
    7. NEW EXERCISE  — no prior data; baseline from predicted 1RM.
    """
    assets = _load_user_model(uid)
    if assets is None:
        raise HTTPException(404, "No trained model. Upload CSV via /train.")
    model, feature_cols, workout_summary = assets

    exercise_history = workout_summary[workout_summary["Exercise"] == req.exercise]
    if exercise_history.empty:
        raise HTTPException(404, "No data found for this exercise.")

    latest_session = exercise_history.iloc[-1]
    last_session_1rm = float(latest_session["Session_Max_1RM"])
    days_since_last_session = float(latest_session["Days_Since_Last"])
    last_max_weight = float(latest_session["Max_Weight"])
    last_avg_reps = float(latest_session["Avg_Reps"])
    last_session_volume = float(latest_session["Volume_Load"])
    last_rep_consistency = float(latest_session.get("Rep_Consistency", 1.0))
    had_form_issues = bool(latest_session.get("Had_Form_Issue", 0))
    had_fatigue = bool(latest_session.get("Had_Fatigue", 0))

    # Momentum: rate of 1RM change across recent sessions.
    # polyfit on 3 sessions is more noise-resistant than a raw diff.
    recent_session_1rms = exercise_history.tail(3)["Session_Max_1RM"].values
    if len(recent_session_1rms) >= 3:
        one_rm_momentum = float(np.polyfit([0, 1, 2], recent_session_1rms, 1)[0])
    elif len(recent_session_1rms) == 2:
        one_rm_momentum = float(recent_session_1rms[-1] - recent_session_1rms[-2])
    else:
        one_rm_momentum = 0.0

    # Plateau detection: peak 1RM across last 4 sessions hasn't improved by
    # 2.5 lbs (smallest standard plate increment) over the starting point.
    last_four_session_1rms = exercise_history.tail(4)["Session_Max_1RM"].values
    is_plateaued = (
        len(last_four_session_1rms) >= 4
        and (last_four_session_1rms.max() - last_four_session_1rms[0]) < 2.5
    )

    # Build a single-row DataFrame mirroring the training feature schema.
    # Start with all zeros so unseen one-hot columns default to 0.
    # CAUTION: special chars in req.exercise (e.g. "[", "]", "<") won't match
    # one-hot column names — model still runs but may be less accurate.
    inference_row = pd.DataFrame({col: [0.0] for col in feature_cols})
    inference_row.at[0, "Days_Since_Last"] = days_since_last_session
    inference_row.at[0, "Previous_1RM"] = last_session_1rm
    inference_row.at[0, "Last_Avg_Reps"] = last_avg_reps
    inference_row.at[0, "Prev_Volume_Load"] = last_session_volume
    inference_row.at[0, "Prev_Rep_Consistency"] = last_rep_consistency
    inference_row.at[0, "Prev_Form_Issue"] = float(had_form_issues)
    inference_row.at[0, "Prev_Fatigue"] = float(had_fatigue)
    inference_row.at[0, "RM_Momentum"] = one_rm_momentum

    exercise_feature_col = f"Exercise_{req.exercise}"
    if exercise_feature_col in feature_cols:
        inference_row.at[0, exercise_feature_col] = 1.0

    category_feature_col = f"Category_{req.category}"
    if category_feature_col in feature_cols:
        inference_row.at[0, category_feature_col] = 1.0

    inference_row = inference_row[feature_cols].astype(float)
    # CAUTION: XGBoost can predict negative values on extrapolation. The AI
    # OVERRIDE threshold catches most cases, but monitor in production.
    predicted_1rm = float(model.predict(inference_row)[0])

    # Safety thresholds by muscle group. Smaller groups (Shoulders, Arms)
    # are more injury-prone so the threshold is tighter.
    safety_thresholds_by_category = {
        "Legs": 0.95,
        "Chest": 0.95,
        "Back": 0.95,
        "Shoulders": 0.90,
        "Arms": 0.85,
    }
    safety_threshold = safety_thresholds_by_category.get(req.category, 0.95)

    is_strength_mode = req.mode == "strength"
    graduation_reps = 6 if is_strength_mode else 12
    baseline_reps = 5 if is_strength_mode else 10
    stabilization_threshold = 3 if is_strength_mode else 8
    stabilization_reps = 4 if is_strength_mode else 10
    volume_reps = 6 if is_strength_mode else 12
    weight_increment = 5.0 if is_strength_mode else 2.5
    mode_label = "STRENGTH" if is_strength_mode else "HYPERTROPHY"

    if had_form_issues:
        target_weight, target_reps = last_max_weight, baseline_reps
        progression_status = "FORM FOCUS: Repeat weight to nail technique"

    elif is_plateaued:
        target_weight = round(last_max_weight * 0.6 / 2.5) * 2.5
        target_reps = 15
        progression_status = "DELOAD: Plateau — back off to rebuild work capacity"

    elif last_avg_reps >= graduation_reps:
        target_weight = last_max_weight + weight_increment
        target_reps = baseline_reps
        progression_status = f"{mode_label} PROGRESSION: Weight Increased"

    elif last_avg_reps < stabilization_threshold:
        target_weight, target_reps = last_max_weight, stabilization_reps
        progression_status = f"{mode_label} STABILIZATION: Build rep count first"

    else:
        target_weight, target_reps = last_max_weight, volume_reps
        progression_status = f"{mode_label} VOLUME: Push for graduation threshold"

    if last_max_weight == 0:
        target_weight = round(_epley_working_weight(predicted_1rm, 8) / 2.5) * 2.5
        target_reps = 8
        status = "NEW EXERCISE: Baseline"
        required_1rm = float(target_weight * (1 + 0.0333 * target_reps))
    else:
        required_1rm = float(target_weight * (1 + 0.0333 * target_reps))
        if not is_plateaued and predicted_1rm < required_1rm * safety_threshold:
            target_weight = (
                round(_epley_working_weight(predicted_1rm, target_reps) / 2.5) * 2.5
            )
            status = "AI OVERRIDE: Fatigue — weight adjusted for safety"
        else:
            status = progression_status

    insights = []
    if had_form_issues:
        insights.append("Form issues logged last session — prioritize technique today.")
    if is_plateaued:
        insights.append("No 1RM gain in 4 sessions. Deload to 60% to rebuild capacity.")
    if had_fatigue:
        insights.append(
            "Fatigue logged last session — consider a grip aid or extra rest."
        )
    if one_rm_momentum < -2:
        insights.append("1RM declining — deload or extra recovery may help.")
    elif one_rm_momentum > 5:
        insights.append("Strong momentum — 1RM climbing consistently!")

    return {
        "target_reps": int(target_reps),
        "target_weight": float(target_weight),
        "status": status,
        "predicted_1rm": predicted_1rm,
        "required_1rm": required_1rm,
        "notes_insight": " ".join(insights),
    }


@app.delete("/delete-user-data")
def delete_user_data(uid: str = Depends(get_uid)):
    """Delete all locally stored model data for the user.

    Removes the on-disk model directory and the in-process cache entry.
    Best-effort — always returns 200 so the client can proceed with cleanup.
    """
    _model_cache.pop(uid, None)
    shutil.rmtree(_model_dir(uid), ignore_errors=True)
    return {"message": "All user data deleted."}

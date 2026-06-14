"""Workout ML — FastAPI backend serving per-user XGBoost models.

Endpoints
---------
POST   /train             Retrain the user's XGBoost model from a CSV.
GET    /exercises         List exercises from the user's training history.
POST   /recommend         Return an AI weight/rep target for a given exercise.
DELETE /delete-user-data  Wipe all cloud data and the Firebase Auth account.

Every route requires a Firebase ID token in ``Authorization: Bearer <token>``.
"""

import io
import os
import time
from datetime import datetime, timedelta, timezone
from typing import Optional

import firebase_admin
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
from firebase_admin import auth as firebase_auth
from firebase_admin import firestore as admin_firestore
from google.cloud import firestore as gcp_firestore
from google.cloud import storage as gcs
from pydantic import BaseModel

from pipeline import run_pipeline

app = FastAPI(title="Workout ML API")

try:
    firebase_admin.get_app()
except ValueError:
    firebase_admin.initialize_app()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

_GCS_BUCKET = os.getenv("GCS_BUCKET", "workout-ml-user-models")
_gcs_client = gcs.Client()

# In-process FIFO cache for loaded models. Capped so Cloud Run memory stays
# bounded regardless of how many distinct users are active on one instance.
# Entries expire after _MODEL_CACHE_TTL seconds so retraining propagates to
# all Cloud Run instances within that window.
_CACHE_MAX = 50
_MAX_CSV_BYTES = 50 * 1024 * 1024  # 50 MB hard cap on training uploads
_MODEL_CACHE_TTL = 300.0  # seconds; bounds post-retrain staleness across instances
_model_cache: dict[str, tuple] = {}
_model_loaded_at: dict[str, float] = {}

# If the server that claimed a training slot crashes before finishing,
# the lock stays "training" in Firestore. Allow reclaim after this window.
_TRAIN_LOCK_TTL = timedelta(minutes=10)


def _gcs_prefix(uid: str) -> str:
    return f"user_models/{uid}"


def _evict_model_cache() -> None:
    """Drop the oldest entry when the model cache is at capacity.

    The cache is a plain dict, which preserves insertion order in Python 3.7+,
    so next(iter(...)) reliably returns the oldest entry.
    """
    if len(_model_cache) >= _CACHE_MAX:
        oldest_uid = next(iter(_model_cache))
        del _model_cache[oldest_uid]
        _model_loaded_at.pop(oldest_uid, None)


def _training_status_ref(uid: str):
    """Return the Firestore document ref that tracks this user's training job."""
    return (
        admin_firestore.client()
        .collection("users")
        .document(uid)
        .collection("trainingStatus")
        .document("current")
    )


def _delete_firestore_collection(col_ref, batch_size: int = 400) -> None:
    """Delete all documents in a Firestore collection reference in batches.

    Firestore doesn't support deleting an entire collection in one call, so
    we page through documents and commit batches of up to batch_size deletes.
    """
    db = admin_firestore.client()
    while True:
        docs = list(col_ref.limit(batch_size).stream())
        if not docs:
            break
        batch = db.batch()
        for doc in docs:
            batch.delete(doc.reference)
        batch.commit()


def _save_user_model(
    uid: str, model, feature_cols: list, session_summary: pd.DataFrame
) -> None:
    """Upload model artifacts to GCS and warm the in-process cache.

    Three files are stored per user: the XGBoost model, the feature column
    list (needed to construct inference rows), and the session summary CSV
    (used to look up last-session stats at recommendation time).
    """
    bucket = _gcs_client.bucket(_GCS_BUCKET)
    prefix = _gcs_prefix(uid)

    for filename, obj in [
        ("xgb_model.joblib", model),
        ("feature_cols.joblib", feature_cols),
    ]:
        buf = io.BytesIO()
        joblib.dump(obj, buf)
        buf.seek(0)
        bucket.blob(f"{prefix}/{filename}").upload_from_file(
            buf, content_type="application/octet-stream"
        )

    csv_buf = io.BytesIO(session_summary.to_csv(index=False).encode())
    bucket.blob(f"{prefix}/workout_summary.csv").upload_from_file(
        csv_buf, content_type="text/csv"
    )

    _evict_model_cache()
    _model_cache[uid] = (model, feature_cols, session_summary)
    _model_loaded_at[uid] = time.monotonic()


def _load_user_model(uid: str) -> tuple | None:
    """Return (model, feature_cols, session_summary) from cache or GCS.

    Returns None if no model has been trained yet.
    Cached entries are invalidated after _MODEL_CACHE_TTL seconds so that a
    freshly retrained model propagates to all Cloud Run instances within one
    TTL window rather than being stuck behind a stale in-process copy.
    """
    if uid in _model_cache:
        cache_age_seconds = time.monotonic() - _model_loaded_at.get(uid, 0.0)
        if cache_age_seconds < _MODEL_CACHE_TTL:
            return _model_cache[uid]
        # Cache entry is stale — remove it and fall through to GCS.
        del _model_cache[uid]
        _model_loaded_at.pop(uid, None)

    # CAUTION: if GCS is unavailable (network issue, wrong bucket name, missing
    # IAM permissions) this silently returns None, and the caller raises 404.
    # Errors are intentionally swallowed here so a GCS outage doesn't surface
    # confusing 500s to the client; the 404 message tells them to retrain.
    try:
        bucket = _gcs_client.bucket(_GCS_BUCKET)
        prefix = _gcs_prefix(uid)

        model = joblib.load(
            io.BytesIO(bucket.blob(f"{prefix}/xgb_model.joblib").download_as_bytes())
        )
        feature_cols = joblib.load(
            io.BytesIO(bucket.blob(f"{prefix}/feature_cols.joblib").download_as_bytes())
        )
        session_summary = pd.read_csv(
            io.BytesIO(
                bucket.blob(f"{prefix}/workout_summary.csv").download_as_bytes()
            ),
            parse_dates=["Date"],
        )

        _evict_model_cache()
        _model_cache[uid] = (model, feature_cols, session_summary)
        _model_loaded_at[uid] = time.monotonic()
        return _model_cache[uid]
    except Exception:  # noqa: BLE001
        return None


def get_uid(authorization: Optional[str] = Header(None)) -> str:
    """FastAPI dependency — verify the Firebase Bearer token and return the UID.

    Raises 401 if the header is missing or the token is invalid/expired.
    """
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(401, "Missing Authorization header.")
    token = authorization.removeprefix("Bearer ")
    try:
        return firebase_auth.verify_id_token(token)["uid"]
    except Exception as exc:
        raise HTTPException(401, f"Invalid token: {exc}") from exc


def _run_train(uid: str, csv_bytes: bytes) -> None:
    """Run the ML pipeline and persist the result to GCS.

    This runs as a FastAPI BackgroundTask so the HTTP response returns
    immediately (202-style). Training progress is written to Firestore so
    clients can watch ``trainingStatus/current`` for updates. A Firestore
    error will never abort the training run itself — the update is best-effort.
    """
    status_ref = _training_status_ref(uid)
    try:
        model, feature_cols, session_summary = run_pipeline(io.BytesIO(csv_bytes))
        _save_user_model(uid, model, feature_cols, session_summary)
        try:
            status_ref.set(
                {
                    "status": "complete",
                    "completedAt": admin_firestore.SERVER_TIMESTAMP,
                }
            )
        except Exception:  # noqa: BLE001
            pass
        print(f"Training complete for {uid}")
    except Exception as exc:  # noqa: BLE001
        try:
            status_ref.set(
                {
                    "status": "failed",
                    "error": str(exc),
                    "failedAt": admin_firestore.SERVER_TIMESTAMP,
                }
            )
        except Exception:  # noqa: BLE001
            pass
        print(f"Training error for {uid}: {exc}")


@app.post("/train")
async def train_model(
    background_tasks: BackgroundTasks,
    file: UploadFile = File(...),
    uid: str = Depends(get_uid),
):
    """Accept a CSV upload and queue a background model retrain.

    A Firestore transaction atomically claims the training slot before
    queuing the job, preventing concurrent submissions from racing on the
    same GCS artifacts across multiple Cloud Run instances. Watch
    ``trainingStatus/current`` for progress.
    """
    if not file.filename.endswith(".csv"):
        raise HTTPException(400, "Only CSV files are allowed.")

    db = admin_firestore.client()
    training_status_ref = _training_status_ref(uid)

    @gcp_firestore.transactional
    def _claim_training_slot(transaction):
        """Atomically check and claim the training lock in Firestore.

        Returns True if this request successfully claimed the slot,
        False if another training job is already running.
        """
        snapshot = training_status_ref.get(transaction=transaction)
        if snapshot.exists:
            doc = snapshot.to_dict()
            if doc.get("status") == "training":
                started_at = doc.get("startedAt")
                # Allow reclaim if the lock is older than _TRAIN_LOCK_TTL —
                # the server that set it probably crashed mid-training.
                if started_at is None:
                    return False
                if datetime.now(timezone.utc) - started_at < _TRAIN_LOCK_TTL:
                    return False
        transaction.set(
            training_status_ref,
            {
                "status": "training",
                "startedAt": admin_firestore.SERVER_TIMESTAMP,
            },
        )
        return True

    if not _claim_training_slot(db.transaction()):
        raise HTTPException(409, "Training already in progress for this account.")

    try:
        csv_bytes = await file.read()
    except Exception:
        try:
            training_status_ref.set(
                {
                    "status": "failed",
                    "error": "File upload failed.",
                    "failedAt": admin_firestore.SERVER_TIMESTAMP,
                }
            )
        except Exception:  # noqa: BLE001
            pass
        raise HTTPException(400, "Failed to read uploaded file.")

    if len(csv_bytes) > _MAX_CSV_BYTES:
        raise HTTPException(
            413,
            f"File too large. Maximum size is {_MAX_CSV_BYTES // (1024 * 1024)} MB.",
        )

    background_tasks.add_task(_run_train, uid, csv_bytes)
    return {"message": "Training started. Watch trainingStatus/current."}


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
    Used everywhere a human-readable plate weight is needed from a raw 1RM.
    """
    return one_rm / (1 + 0.0333 * target_reps)


@app.post("/recommend")
def get_recommendation(req: WorkoutRequest, uid: str = Depends(get_uid)):
    """Return an AI-generated weight and rep target for the given exercise.

    Decision logic (in priority order):
    1. FORM FOCUS   — technique issues logged last session; repeat weight.
    2. DELOAD       — 4-session plateau detected; drop to 60% to reset fatigue.
    3. PROGRESSION  — hit graduation reps last session; bump weight.
    4. STABILIZATION— reps too low to safely progress; build rep count first.
    5. VOLUME       — in the working rep range; push toward graduation target.
    6. AI OVERRIDE  — XGBoost predicts capacity too low for the planned load;
                      scale weight down to keep the session safe.
    7. NEW EXERCISE — no prior data; baseline from predicted 1RM.
    """
    assets = _load_user_model(uid)
    if assets is None:
        raise HTTPException(404, "No trained model. Upload CSV via /train.")
    model, feature_cols, workout_summary = assets

    exercise_history = workout_summary[workout_summary["Exercise"] == req.exercise]
    if exercise_history.empty:
        raise HTTPException(404, "No data found for this exercise.")

    # Pull last-session values from the most recent row in the exercise history.
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
    # polyfit on 3 sessions is more noise-resistant than a raw session-to-session diff.
    recent_session_1rms = exercise_history.tail(3)["Session_Max_1RM"].values
    if len(recent_session_1rms) >= 3:
        one_rm_momentum = float(np.polyfit([0, 1, 2], recent_session_1rms, 1)[0])
    elif len(recent_session_1rms) == 2:
        # Only 2 sessions available — simple difference is the best we can do.
        one_rm_momentum = float(recent_session_1rms[-1] - recent_session_1rms[-2])
    else:
        one_rm_momentum = 0.0

    # Plateau detection: if the peak 1RM across the last 4 sessions hasn't
    # improved by at least 2.5 lbs over the starting point, the lifter is stuck.
    # 2.5 lbs is the smallest standard plate increment — any gain below that
    # is practically unmeasurable and likely noise.
    last_four_session_1rms = exercise_history.tail(4)["Session_Max_1RM"].values
    is_plateaued = (
        len(last_four_session_1rms) >= 4
        and (last_four_session_1rms.max() - last_four_session_1rms[0]) < 2.5
    )

    # Build a single-row DataFrame that mirrors the training feature schema.
    # Start with all zeros so unseen one-hot columns default to "not this exercise."
    # CAUTION: if req.exercise contains characters that pandas replaces during
    # get_dummies (e.g. "[", "]", "<"), the column name won't match feature_cols
    # and the one-hot flag stays 0 — the model will still run but may be less accurate.
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
    # CAUTION: XGBoost can predict negative values on extrapolation (e.g. very
    # long rest, unusual rep count). Downstream logic divides by predicted_1rm
    # via _epley_working_weight, so a zero or negative value would produce
    # nonsensical weights. Currently handled implicitly because the AI OVERRIDE
    # threshold check catches low predictions, but worth monitoring in production.
    predicted_1rm = float(model.predict(inference_row)[0])

    # Safety thresholds: the fraction of predicted capacity that must be met
    # before suggesting a weight increase. Larger muscle groups (Legs, Chest,
    # Back) tolerate heavier loads and are penalised less; smaller groups
    # (Shoulders, Arms) are more injury-prone so the threshold is tighter.
    safety_thresholds_by_category = {
        "Legs": 0.95,
        "Chest": 0.95,
        "Back": 0.95,
        "Shoulders": 0.90,
        "Arms": 0.85,
    }
    safety_threshold = safety_thresholds_by_category.get(req.category, 0.95)

    # Mode-specific rep scheme parameters.
    # Strength: lower rep targets, larger weight increments (5 lb jumps).
    # Hypertrophy: higher rep targets, smaller increments (2.5 lb jumps).
    is_strength_mode = req.mode == "strength"
    graduation_reps = (
        6 if is_strength_mode else 12
    )  # reps needed to earn a weight increase
    baseline_reps = 5 if is_strength_mode else 10  # reps suggested after a weight jump
    stabilization_threshold = (
        3 if is_strength_mode else 8
    )  # reps below which we stop weight progress
    stabilization_reps = (
        4 if is_strength_mode else 10
    )  # reps target while building rep capacity
    volume_reps = 6 if is_strength_mode else 12  # reps target in the "push" zone
    weight_increment = 5.0 if is_strength_mode else 2.5
    mode_label = "STRENGTH" if is_strength_mode else "HYPERTROPHY"

    # Primary decision tree — sets the initial target before the safety check.
    if had_form_issues:
        # Repeating the same weight forces focus on technique rather than load.
        target_weight, target_reps = last_max_weight, baseline_reps
        progression_status = "FORM FOCUS: Repeat weight to nail technique"

    elif is_plateaued:
        # Deload to 60% to flush accumulated fatigue and reset the nervous system.
        target_weight = round(last_max_weight * 0.6 / 2.5) * 2.5
        target_reps = 15  # high reps at low intensity rebuild aerobic base
        progression_status = "DELOAD: Plateau — back off to rebuild work capacity"

    elif last_avg_reps >= graduation_reps:
        # Hit the graduation threshold last session — earned the next weight plate.
        target_weight = last_max_weight + weight_increment
        target_reps = baseline_reps
        progression_status = f"{mode_label} PROGRESSION: Weight Increased"

    elif last_avg_reps < stabilization_threshold:
        # Rep count is too low to safely add weight — first build rep capacity.
        target_weight, target_reps = last_max_weight, stabilization_reps
        progression_status = f"{mode_label} STABILIZATION: Build rep count first"

    else:
        # In the working range — push reps toward the graduation threshold.
        target_weight, target_reps = last_max_weight, volume_reps
        progression_status = f"{mode_label} VOLUME: Push for graduation threshold"

    # New exercise override: no prior weight data, so derive a starting point
    # from the model's predicted 1RM rather than an empty last_max_weight.
    if last_max_weight == 0:
        target_weight = round(_epley_working_weight(predicted_1rm, 8) / 2.5) * 2.5
        target_reps = 8
        status = "NEW EXERCISE: Baseline"
        required_1rm = float(target_weight * (1 + 0.0333 * target_reps))

    else:
        # required_1rm is what the lifter would need to handle target_weight × target_reps.
        # If the model predicts they can't reach safety_threshold × required_1rm,
        # the weight is scaled back to what they can actually handle today.
        required_1rm = float(target_weight * (1 + 0.0333 * target_reps))
        if not is_plateaued and predicted_1rm < required_1rm * safety_threshold:
            # AI OVERRIDE: predicted capacity is too low for the planned load.
            # Scale weight to what the model thinks is achievable at target_reps.
            target_weight = (
                round(_epley_working_weight(predicted_1rm, target_reps) / 2.5) * 2.5
            )
            status = "AI OVERRIDE: Fatigue — weight adjusted for safety"
        else:
            status = progression_status

    # Collect insight strings shown to the user below the recommendation.
    insights = []
    if had_form_issues:
        insights.append("Form issues logged last session — prioritize technique today.")
    if is_plateaued:
        insights.append("No 1RM gain in 4 sessions. Deload to 60% to rebuild capacity.")
    if had_fatigue:
        insights.append(
            "Fatigue logged last session — consider a grip aid or extra rest."
        )
    # Momentum thresholds: < -2 means the trend is meaningfully downward;
    # > 5 means genuine upward progress worth calling out.
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
    """Delete all cloud data for the authenticated user.

    Removes GCS model artifacts, Firestore subcollections, in-process
    cache entries, and the Firebase Auth account. Clients should sign
    out and clear local storage after this returns.

    All steps are best-effort — a failure in one does not abort the
    others, and the endpoint always returns 200 so the client can
    proceed with local cleanup.
    """
    _model_cache.pop(uid, None)
    _model_loaded_at.pop(uid, None)

    try:
        bucket = _gcs_client.bucket(_GCS_BUCKET)
        blobs = list(bucket.list_blobs(prefix=f"user_models/{uid}/"))
        for blob in blobs:
            blob.delete()
    except Exception:  # noqa: BLE001
        pass

    try:
        db = admin_firestore.client()
        user_ref = db.collection("users").document(uid)
        for collection_name in ("sets", "trainingStatus"):
            _delete_firestore_collection(user_ref.collection(collection_name))
        user_ref.delete()
    except Exception:  # noqa: BLE001
        pass

    try:
        firebase_auth.delete_user(uid)
    except Exception:  # noqa: BLE001
        pass

    return {"message": "All user data deleted."}

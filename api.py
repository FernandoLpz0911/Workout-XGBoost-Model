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
_MODEL_CACHE_TTL = 300.0  # seconds; bounds post-retrain cross-instance staleness
_model_cache: dict[str, tuple] = {}
_model_loaded_at: dict[str, float] = {}

# If the server that claimed a training slot crashes before finishing,
# the lock stays "training" in Firestore. Allow reclaim after this window.
_TRAIN_LOCK_TTL = timedelta(minutes=10)


def _gcs_prefix(uid: str) -> str:
    return f"user_models/{uid}"


def _evict_model_cache() -> None:
    """Drop the oldest entry when the model cache is at capacity."""
    if len(_model_cache) >= _CACHE_MAX:
        oldest_uid = next(iter(_model_cache))
        del _model_cache[oldest_uid]
        _model_loaded_at.pop(oldest_uid, None)


def _training_status_ref(uid: str):
    """Return the Firestore ref for the user's training-status document."""
    return (
        admin_firestore.client()
        .collection("users").document(uid)
        .collection("trainingStatus").document("current")
    )


def _delete_firestore_collection(col_ref, batch_size: int = 400) -> None:
    """Delete all documents in a Firestore collection reference in batches."""
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
    uid: str, model, feature_cols: list, summary: pd.DataFrame
) -> None:
    """Upload model, feature list, and summary CSV to GCS, then warm cache."""
    bucket = _gcs_client.bucket(_GCS_BUCKET)
    prefix = _gcs_prefix(uid)

    for name, obj in [
        ("xgb_model.joblib", model),
        ("feature_cols.joblib", feature_cols),
    ]:
        buf = io.BytesIO()
        joblib.dump(obj, buf)
        buf.seek(0)
        bucket.blob(f"{prefix}/{name}").upload_from_file(
            buf, content_type="application/octet-stream"
        )

    csv_buf = io.BytesIO(summary.to_csv(index=False).encode())
    bucket.blob(f"{prefix}/workout_summary.csv").upload_from_file(
        csv_buf, content_type="text/csv"
    )

    _evict_model_cache()
    _model_cache[uid] = (model, feature_cols, summary)
    _model_loaded_at[uid] = time.monotonic()


def _load_user_model(uid: str) -> tuple | None:
    """Return ``(model, feature_cols, summary)`` from cache or GCS.

    Returns None if no model has been trained yet. Cached entries expire
    after ``_MODEL_CACHE_TTL`` seconds, bounding cross-instance staleness
    after a user retrains to one TTL window.
    """
    if uid in _model_cache:
        age = time.monotonic() - _model_loaded_at.get(uid, 0.0)
        if age < _MODEL_CACHE_TTL:
            return _model_cache[uid]
        del _model_cache[uid]
        _model_loaded_at.pop(uid, None)
    try:
        bucket = _gcs_client.bucket(_GCS_BUCKET)
        prefix = _gcs_prefix(uid)
        model_buf = io.BytesIO(
            bucket.blob(f"{prefix}/xgb_model.joblib").download_as_bytes()
        )
        cols_buf = io.BytesIO(
            bucket.blob(
                f"{prefix}/feature_cols.joblib"
            ).download_as_bytes()
        )
        csv_bytes = (
            bucket.blob(f"{prefix}/workout_summary.csv").download_as_bytes()
        )
        model = joblib.load(model_buf)
        feature_cols = joblib.load(cols_buf)
        summary = pd.read_csv(io.BytesIO(csv_bytes), parse_dates=["Date"])
        _evict_model_cache()
        _model_cache[uid] = (model, feature_cols, summary)
        _model_loaded_at[uid] = time.monotonic()
        return _model_cache[uid]
    except Exception:  # noqa: BLE001
        return None


def get_uid(authorization: Optional[str] = Header(None)) -> str:
    """FastAPI dependency — verify the Bearer token and return the UID."""
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(401, "Missing Authorization header.")
    token = authorization.removeprefix("Bearer ")
    try:
        return firebase_auth.verify_id_token(token)["uid"]
    except Exception as exc:
        raise HTTPException(401, f"Invalid token: {exc}") from exc


def _run_train(uid: str, csv_bytes: bytes) -> None:
    """Run the ML pipeline and persist the result to GCS.

    Invoked as a FastAPI background task so the HTTP response returns
    immediately. Training status is written to Firestore (best-effort) so
    clients can watch ``trainingStatus/current`` for progress. A Firestore
    error will never abort the training run itself.
    """
    ref = _training_status_ref(uid)
    try:
        model, feature_cols, summary = run_pipeline(io.BytesIO(csv_bytes))
        _save_user_model(uid, model, feature_cols, summary)
        try:
            ref.set({
                "status": "complete",
                "completedAt": admin_firestore.SERVER_TIMESTAMP,
            })
        except Exception:  # noqa: BLE001
            pass
        print(f"Training complete for {uid}")
    except Exception as exc:  # noqa: BLE001
        try:
            ref.set({
                "status": "failed",
                "error": str(exc),
                "failedAt": admin_firestore.SERVER_TIMESTAMP,
            })
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
    ref = _training_status_ref(uid)

    @gcp_firestore.transactional
    def _claim(transaction):
        snap = ref.get(transaction=transaction)
        if snap.exists:
            doc = snap.to_dict()
            if doc.get("status") == "training":
                started = doc.get("startedAt")
                # Allow reclaim if the slot is older than _TRAIN_LOCK_TTL.
                # Missing or recent timestamp means training is active.
                if started is None:
                    return False
                if datetime.now(timezone.utc) - started < _TRAIN_LOCK_TTL:
                    return False
        transaction.set(ref, {
            "status": "training",
            "startedAt": admin_firestore.SERVER_TIMESTAMP,
        })
        return True

    if not _claim(db.transaction()):
        raise HTTPException(
            409, "Training already in progress for this account."
        )

    try:
        csv_bytes = await file.read()
    except Exception:
        try:
            ref.set({
                "status": "failed",
                "error": "File upload failed.",
                "failedAt": admin_firestore.SERVER_TIMESTAMP,
            })
        except Exception:  # noqa: BLE001
            pass
        raise HTTPException(400, "Failed to read uploaded file.")

    if len(csv_bytes) > _MAX_CSV_BYTES:
        raise HTTPException(
            413,
            f"File too large. Maximum size is "
            f"{_MAX_CSV_BYTES // (1024 * 1024)} MB.",
        )

    background_tasks.add_task(_run_train, uid, csv_bytes)
    return {"message": "Training started. Watch trainingStatus/current."}


@app.get("/exercises")
def get_exercises(uid: str = Depends(get_uid)):
    """Return the user's exercise catalogue grouped by category."""
    assets = _load_user_model(uid)
    if assets is None:
        raise HTTPException(404, "No trained model. Upload CSV via /train.")
    _, _, summary = assets
    try:
        return (
            summary.groupby("Category")["Exercise"]
            .unique().apply(list).to_dict()
        )
    except Exception as exc:
        raise HTTPException(500, str(exc)) from exc


class WorkoutRequest(BaseModel):
    category: str
    exercise: str
    mode: str = "hypertrophy"  # "hypertrophy" | "strength"


def _get_weight(one_rm: float, reps: int) -> float:
    """Convert a 1RM estimate to a working weight using the Epley formula."""
    return one_rm / (1 + 0.0333 * reps)


@app.post("/recommend")
def get_recommendation(req: WorkoutRequest, uid: str = Depends(get_uid)):
    """Return an AI-generated weight and rep target for the given exercise."""
    assets = _load_user_model(uid)
    if assets is None:
        raise HTTPException(404, "No trained model. Upload CSV via /train.")
    model, feature_cols, workout_summary = assets

    ex_data = workout_summary[workout_summary["Exercise"] == req.exercise]
    if ex_data.empty:
        raise HTTPException(404, "No data found for this exercise.")

    last = ex_data.iloc[-1]
    last_1rm = float(last["Session_Max_1RM"])
    last_days = float(last["Days_Since_Last"])
    last_w = float(last["Max_Weight"])
    last_reps = float(last["Avg_Reps"])
    last_volume = float(last["Volume_Load"])
    last_rep_cons = float(last.get("Rep_Consistency", 1.0))
    had_form = bool(last.get("Had_Form_Issue", 0))
    had_fatigue = bool(last.get("Had_Fatigue", 0))

    recent_1rms = ex_data.tail(3)["Session_Max_1RM"].values
    if len(recent_1rms) >= 3:
        rm_momentum = float(np.polyfit([0, 1, 2], recent_1rms, 1)[0])
    elif len(recent_1rms) == 2:
        rm_momentum = float(recent_1rms[-1] - recent_1rms[-2])
    else:
        rm_momentum = 0.0

    recent_4 = ex_data.tail(4)["Session_Max_1RM"].values
    plateau = len(recent_4) >= 4 and (recent_4.max() - recent_4[0]) < 2.5

    sim = pd.DataFrame({col: [0.0] for col in feature_cols})
    sim.at[0, "Days_Since_Last"] = last_days
    sim.at[0, "Previous_1RM"] = last_1rm
    sim.at[0, "Last_Avg_Reps"] = last_reps
    sim.at[0, "Prev_Volume_Load"] = last_volume
    sim.at[0, "Prev_Rep_Consistency"] = last_rep_cons
    sim.at[0, "Prev_Form_Issue"] = float(had_form)
    sim.at[0, "Prev_Fatigue"] = float(had_fatigue)
    sim.at[0, "RM_Momentum"] = rm_momentum
    if (ex_col := f"Exercise_{req.exercise}") in feature_cols:
        sim.at[0, ex_col] = 1.0
    if (cat_col := f"Category_{req.category}") in feature_cols:
        sim.at[0, cat_col] = 1.0

    sim = sim[feature_cols].astype(float)
    pred_1rm = float(model.predict(sim)[0])

    thresholds = {
        "Legs": 0.95, "Chest": 0.95, "Back": 0.95,
        "Shoulders": 0.90, "Arms": 0.85,
    }
    threshold = thresholds.get(req.category, 0.95)

    is_strength = req.mode == "strength"
    graduation_reps = 6 if is_strength else 12
    default_reps = 5 if is_strength else 10
    stabilize_threshold = 3 if is_strength else 8
    stabilize_reps = 4 if is_strength else 10
    volume_reps = 6 if is_strength else 12
    weight_increment = 5.0 if is_strength else 2.5
    mode_label = "STRENGTH" if is_strength else "HYPERTROPHY"

    if had_form:
        target_w, target_r = last_w, default_reps
        base_status = "FORM FOCUS: Repeat weight to nail technique"
    elif plateau:
        target_w = round(last_w * 0.6 / 2.5) * 2.5
        target_r = 15
        base_status = "DELOAD: Plateau — back off to rebuild work capacity"
    elif last_reps >= graduation_reps:
        target_w = last_w + weight_increment
        target_r = default_reps
        base_status = f"{mode_label} PROGRESSION: Weight Increased"
    elif last_reps < stabilize_threshold:
        target_w, target_r = last_w, stabilize_reps
        base_status = f"{mode_label} STABILIZATION: Build rep count first"
    else:
        target_w, target_r = last_w, volume_reps
        base_status = f"{mode_label} VOLUME: Push for graduation threshold"

    if last_w == 0:
        target_w = round(_get_weight(pred_1rm, 8) / 2.5) * 2.5
        target_r = 8
        status = "NEW EXERCISE: Baseline"
        required_1rm = float(target_w * (1 + 0.0333 * target_r))
    else:
        required_1rm = float(target_w * (1 + 0.0333 * target_r))
        if not plateau and pred_1rm < required_1rm * threshold:
            target_w = round(_get_weight(pred_1rm, target_r) / 2.5) * 2.5
            status = "AI OVERRIDE: Fatigue — weight adjusted for safety"
        else:
            status = base_status

    insights = []
    if had_form:
        insights.append(
            "Form issues logged last session — prioritize technique today."
        )
    if plateau:
        insights.append(
            "No 1RM gain in 4 sessions. Deload to 60% to rebuild capacity."
        )
    if had_fatigue:
        insights.append(
            "Fatigue logged last session — consider a grip aid or extra rest."
        )
    if rm_momentum < -2:
        insights.append("1RM declining — deload or extra recovery may help.")
    elif rm_momentum > 5:
        insights.append("Strong momentum — 1RM climbing consistently!")

    return {
        "target_reps": int(target_r),
        "target_weight": float(target_w),
        "status": status,
        "predicted_1rm": pred_1rm,
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
        for col_name in ("sets", "trainingStatus"):
            _delete_firestore_collection(user_ref.collection(col_name))
        user_ref.delete()
    except Exception:  # noqa: BLE001
        pass

    try:
        firebase_auth.delete_user(uid)
    except Exception:  # noqa: BLE001
        pass

    return {"message": "All user data deleted."}

"""Workout ML — FastAPI backend serving per-user XGBoost models."""

import io
import os
import time
from typing import Optional

import firebase_admin
import joblib
import numpy as np
import pandas as pd
from firebase_admin import auth as firebase_auth
from firebase_admin import firestore as admin_firestore
from fastapi import (
    BackgroundTasks, Depends, FastAPI, Header, HTTPException, UploadFile, File
)
from fastapi.middleware.cors import CORSMiddleware
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

# Capped at _CACHE_MAX entries. Oldest UID evicted when limit hit so Cloud Run
# memory stays bounded regardless of how many users train models.
_CACHE_MAX = 50
_model_cache: dict[str, tuple] = {}

# Premium status cached for _PREMIUM_TTL seconds to avoid a Firestore read on
# every /train and /recommend call. uid → (is_premium, expiry_monotonic)
# Capped at _PREMIUM_CACHE_MAX entries with FIFO eviction (same as _model_cache).
_PREMIUM_TTL = 60.0
_PREMIUM_CACHE_MAX = 500
_premium_cache: dict[str, tuple[bool, float]] = {}

# UIDs with a background training job currently running. Checked in /train to
# reject concurrent submissions and prevent GCS / Firestore write races.
_training_in_progress: set[str] = set()

_gcs_client = gcs.Client()


def _gcs_prefix(uid: str) -> str:
    return f"user_models/{uid}"


def _evict_if_needed() -> None:
    if len(_model_cache) >= _CACHE_MAX:
        del _model_cache[next(iter(_model_cache))]


def _save_user_model(
    uid: str, model, feature_cols: list, summary: pd.DataFrame
) -> None:
    """Serialize and upload all three artifacts to GCS, then update cache."""
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

    _evict_if_needed()
    _model_cache[uid] = (model, feature_cols, summary)


def _load_user_model(uid: str) -> tuple | None:
    """Load from cache or GCS. None if no model exists for this user."""
    if uid in _model_cache:
        return _model_cache[uid]
    try:
        bucket = _gcs_client.bucket(_GCS_BUCKET)
        prefix = _gcs_prefix(uid)
        model_buf = io.BytesIO(
            bucket.blob(f"{prefix}/xgb_model.joblib").download_as_bytes()
        )
        cols_buf = io.BytesIO(
            bucket.blob(f"{prefix}/feature_cols.joblib").download_as_bytes()
        )
        csv_bytes = bucket.blob(
            f"{prefix}/workout_summary.csv"
        ).download_as_bytes()
        model = joblib.load(model_buf)
        feature_cols = joblib.load(cols_buf)
        summary = pd.read_csv(io.BytesIO(csv_bytes), parse_dates=["Date"])
        _evict_if_needed()
        _model_cache[uid] = (model, feature_cols, summary)
        return _model_cache[uid]
    except Exception:  # noqa: BLE001
        return None


# ── Auth ──────────────────────────────────────────────────────────────────────


def get_uid(authorization: Optional[str] = Header(None)) -> str:
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(401, "Missing Authorization header.")
    token = authorization.removeprefix("Bearer ")
    try:
        return firebase_auth.verify_id_token(token)["uid"]
    except Exception as exc:
        raise HTTPException(401, f"Invalid token: {exc}") from exc


def require_premium(uid: str = Depends(get_uid)) -> str:
    now = time.monotonic()
    cached = _premium_cache.get(uid)
    if cached is not None and now < cached[1]:
        if not cached[0]:
            raise HTTPException(403, "Active Premium subscription required.")
        return uid
    db = admin_firestore.client()
    doc = db.collection("users").document(uid).get()
    if not doc.exists:
        raise HTTPException(403, "No user record found.")
    is_premium = doc.to_dict().get("subscriptionStatus") == "active"
    if len(_premium_cache) >= _PREMIUM_CACHE_MAX:
        del _premium_cache[next(iter(_premium_cache))]
    _premium_cache[uid] = (is_premium, now + _PREMIUM_TTL)
    if not is_premium:
        raise HTTPException(403, "Active Premium subscription required.")
    return uid


# ── Endpoints ─────────────────────────────────────────────────────────────────


def _run_train(uid: str, csv_bytes: bytes) -> None:
    """Train model and save to GCS. Runs in a FastAPI background task."""
    _training_in_progress.add(uid)
    db = admin_firestore.client()
    status_ref = (
        db.collection("users").document(uid)
        .collection("trainingStatus").document("current")
    )
    try:
        try:
            status_ref.set({
                "status": "training",
                "startedAt": admin_firestore.SERVER_TIMESTAMP,
            })
        except Exception:  # noqa: BLE001
            pass  # never let a status write abort the training run
        try:
            model, feature_cols, summary = run_pipeline(io.BytesIO(csv_bytes))
            _save_user_model(uid, model, feature_cols, summary)
            try:
                status_ref.set({
                    "status": "complete",
                    "completedAt": admin_firestore.SERVER_TIMESTAMP,
                })
            except Exception:  # noqa: BLE001
                pass
            print(f"Training complete for {uid}")
        except Exception as exc:  # noqa: BLE001
            try:
                status_ref.set({
                    "status": "failed",
                    "error": str(exc),
                    "failedAt": admin_firestore.SERVER_TIMESTAMP,
                })
            except Exception:  # noqa: BLE001
                pass
            print(f"Training error for {uid}: {exc}")
    finally:
        _training_in_progress.discard(uid)


@app.post("/train")
async def train_model(
    background_tasks: BackgroundTasks,
    file: UploadFile = File(...),
    uid: str = Depends(require_premium),
):
    """Upload CSV, retrain model in background, return immediately."""
    if not file.filename.endswith(".csv"):
        raise HTTPException(400, "Only CSV files are allowed.")
    if uid in _training_in_progress:
        raise HTTPException(409, "Training already in progress for this account.")
    csv_bytes = await file.read()
    background_tasks.add_task(_run_train, uid, csv_bytes)
    return {"message": "Training started. Model will update in the background."}


@app.get("/exercises")
def get_exercises(uid: str = Depends(get_uid)):
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


def _get_weight(one_rm: float, reps: int) -> float:
    return one_rm / (1 + 0.0333 * reps)


@app.post("/recommend")
def get_recommendation(req: WorkoutRequest, uid: str = Depends(get_uid)):
    """Return AI recommendation for the exercise (auth required)."""
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

    thresholds = {"Legs": 0.95, "Chest": 0.95, "Back": 0.95,
                  "Shoulders": 0.90, "Arms": 0.85}
    threshold = thresholds.get(req.category, 0.95)

    if had_form:
        target_w, target_r = last_w, 8
        base_status = "FORM FOCUS: Repeat weight to nail technique"
    elif plateau:
        target_w = round(last_w * 0.6 / 2.5) * 2.5
        target_r = 15
        base_status = "DELOAD: Plateau — back off to rebuild work capacity"
    elif last_reps >= 10:
        target_w, target_r = last_w + 2.5, 8
        base_status = "PROGRESSION: Weight Increased"
    elif last_reps < 6:
        target_w, target_r = last_w, 8
        base_status = "STABILIZATION: Build rep count first"
    else:
        target_w, target_r = last_w, 10
        base_status = "VOLUME: Push for graduation threshold"

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
            "No 1RM gain in 4 sessions. "
            "Deload at 60% load to rebuild capacity."
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

"""Workout ML — FastAPI backend serving per-user XGBoost models."""

import io
import os
from typing import Optional

import firebase_admin
import joblib
import numpy as np
import pandas as pd
from firebase_admin import auth as firebase_auth
from firebase_admin import firestore as admin_firestore
from fastapi import Depends, FastAPI, Header, HTTPException, UploadFile, File
from fastapi.middleware.cors import CORSMiddleware
from google.cloud import storage as gcs
from pydantic import BaseModel

from pipeline import run_pipeline

app = FastAPI(title="Workout ML API")

if not firebase_admin._apps:
    firebase_admin.initialize_app()

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

# GCS bucket that stores per-user model artifacts.
# Create this bucket in your project before deploying:
#   gsutil mb gs://<your-bucket-name>
# Set the env var GCS_BUCKET on your Cloud Run service to match.
_GCS_BUCKET = os.getenv("GCS_BUCKET", "workout-ml-user-models")

# In-memory cache: uid → (model, feature_cols, workout_summary).
# Each Cloud Run instance caches independently; a cache miss just reloads
# from GCS, which is the same cost as the old global load.
_model_cache: dict[str, tuple] = {}

_gcs_client = gcs.Client()


def _gcs_prefix(uid: str) -> str:
    return f"user_models/{uid}"


def _save_user_model(
    uid: str, model, feature_cols: list, summary: pd.DataFrame
):
    """Serialize and upload all three artifacts to GCS."""
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

        _model_cache[uid] = (model, feature_cols, summary)
        return _model_cache[uid]
    except Exception:
        return None


# ── Auth dependencies ────────────────────────────────────────────────────────


def get_uid(authorization: Optional[str] = Header(None)) -> str:
    """Verify the Firebase ID token and return the caller's UID."""
    if not authorization or not authorization.startswith("Bearer "):
        raise HTTPException(
            status_code=401, detail="Missing Authorization header."
        )
    token = authorization.removeprefix("Bearer ")
    try:
        decoded = firebase_auth.verify_id_token(token)
        return decoded["uid"]
    except Exception as exc:
        raise HTTPException(
            status_code=401, detail=f"Invalid token: {exc}"
        ) from exc


def require_premium(uid: str = Depends(get_uid)) -> str:
    """Extend get_uid by checking for an active subscription in Firestore."""
    db = admin_firestore.client()
    doc = db.collection("users").document(uid).get()
    if not doc.exists:
        raise HTTPException(status_code=403, detail="No user record found.")
    status = doc.to_dict().get("subscriptionStatus", "none")
    if status != "active":
        raise HTTPException(
            status_code=403,
            detail="An active Premium subscription is required.",
        )
    return uid


# ── Endpoints ────────────────────────────────────────────────────────────────


@app.post("/train")
async def train_model(
    file: UploadFile = File(...),
    uid: str = Depends(require_premium),
):
    """Retrain the user's XGBoost model from an uploaded FitNotes CSV."""
    if not file.filename.endswith(".csv"):
        raise HTTPException(
            status_code=400, detail="Only CSV files are allowed."
        )
    try:
        model, feature_cols, summary = run_pipeline(file.file)
        _save_user_model(uid, model, feature_cols, summary)
        return {"message": "Model successfully trained and updated!"}
    except Exception as exc:
        raise HTTPException(
            status_code=500, detail=f"Training error: {str(exc)}"
        ) from exc


@app.get("/exercises")
def get_exercises(uid: str = Depends(get_uid)):
    """Return all exercises the user has trained on, grouped by category."""
    assets = _load_user_model(uid)
    if assets is None:
        raise HTTPException(
            status_code=404,
            detail="No trained model found. Upload a CSV via /train first.",
        )
    _, _, summary = assets
    try:
        return (
            summary
            .groupby("Category")["Exercise"]
            .unique()
            .apply(list)
            .to_dict()
        )
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc)) from exc


class WorkoutRequest(BaseModel):
    """Request body for the /recommend endpoint."""

    category: str
    exercise: str


def _get_weight(one_rm: float, reps: int) -> float:
    """Invert Epley formula: working weight for a target rep count."""
    return one_rm / (1 + 0.0333 * reps)


@app.post("/recommend")
def get_recommendation(
    req: WorkoutRequest,
    uid: str = Depends(get_uid),
):
    """Return AI recommendation for the requested exercise (auth required)."""
    assets = _load_user_model(uid)
    if assets is None:
        raise HTTPException(
            status_code=404,
            detail=(
                "No trained model found. Upload a CSV via /train first."
            ),
        )
    model, feature_cols, workout_summary = assets

    ex_data = workout_summary[workout_summary["Exercise"] == req.exercise]
    if ex_data.empty:
        raise HTTPException(
            status_code=404, detail="No data found for this exercise."
        )

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

    # Plateau detection: 4 sessions with no 1RM gain >= 2.5 lbs.
    recent_4 = ex_data.tail(4)["Session_Max_1RM"].values
    plateau = (
        len(recent_4) >= 4
        and (recent_4.max() - recent_4[0]) < 2.5
    )

    sim = pd.DataFrame({col: [0.0] for col in feature_cols})
    sim.at[0, "Days_Since_Last"] = last_days
    sim.at[0, "Previous_1RM"] = last_1rm
    sim.at[0, "Last_Avg_Reps"] = last_reps
    sim.at[0, "Prev_Volume_Load"] = last_volume
    sim.at[0, "Prev_Rep_Consistency"] = last_rep_cons
    sim.at[0, "Prev_Form_Issue"] = float(had_form)
    sim.at[0, "Prev_Fatigue"] = float(had_fatigue)
    sim.at[0, "RM_Momentum"] = rm_momentum

    ex_col = f"Exercise_{req.exercise}"
    cat_col = f"Category_{req.category}"
    if ex_col in feature_cols:
        sim.at[0, ex_col] = 1.0
    if cat_col in feature_cols:
        sim.at[0, cat_col] = 1.0

    sim = sim[feature_cols].astype(float)
    pred_1rm = float(model.predict(sim)[0])

    override_thresholds = {
        "Legs": 0.95, "Chest": 0.95, "Back": 0.95,
        "Shoulders": 0.90, "Arms": 0.85,
    }
    threshold = override_thresholds.get(req.category, 0.95)

    if had_form:
        target_w = last_w
        target_r = 8
        base_status = "FORM FOCUS: Repeat weight to nail technique"
    elif plateau:
        target_w = round(last_w * 0.6 / 2.5) * 2.5
        target_r = 15
        base_status = (
            "DELOAD: Plateau detected — back off to rebuild work capacity"
        )
    elif last_reps >= 10:
        target_w = last_w + 2.5
        target_r = 8
        base_status = "PROGRESSION: Weight Increased"
    elif last_reps < 6:
        target_w = last_w
        target_r = 8
        base_status = "STABILIZATION: Build rep count first"
    else:
        target_w = last_w
        target_r = 10
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
            status = (
                "AI OVERRIDE: Fatigue detected - weight adjusted for safety"
            )
        else:
            status = base_status

    insights = []
    if had_form:
        insights.append(
            "Form issues were logged last session"
            " - prioritize technique over load today."
        )
    if plateau:
        insights.append(
            "No 1RM gain across the last 4 sessions."
            " Deload at 60% load with higher reps to rebuild capacity."
        )
    if had_fatigue:
        insights.append(
            "Grip or muscle fatigue was logged last session"
            " - consider a grip aid, looser grip cue, or an extra rest day."
        )
    if rm_momentum < -2:
        insights.append(
            "1RM has been declining over recent sessions"
            " - a deload week or extra recovery day may help."
        )
    elif rm_momentum > 5:
        insights.append(
            "Strong momentum - your 1RM has been climbing consistently!"
        )

    return {
        "target_reps": int(target_r),
        "target_weight": float(target_w),
        "status": status,
        "predicted_1rm": pred_1rm,
        "required_1rm": required_1rm,
        "notes_insight": " ".join(insights),
    }

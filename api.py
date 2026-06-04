"""Workout ML — FastAPI backend serving the XGBoost recommendation model."""

from typing import Optional

import firebase_admin
import joblib
import numpy as np
import pandas as pd
from firebase_admin import auth as firebase_auth
from firebase_admin import firestore as admin_firestore
from fastapi import Depends, FastAPI, Header, HTTPException, UploadFile, File
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

from pipeline import run_pipeline

app = FastAPI(title="Workout ML API")

# Initialise Firebase Admin using Application Default Credentials.
# On Cloud Run the service account is picked up automatically.
if not firebase_admin._apps:
    firebase_admin.initialize_app()

# CORS: native mobile clients are not subject to browser CORS restrictions.
# Security is enforced entirely via Firebase token validation.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)


def _load_assets():
    try:
        return (
            joblib.load("xgb_model.joblib"),
            joblib.load("feature_cols.joblib"),
            pd.read_csv("Processed_Workout_Data.csv", parse_dates=["Date"]),
        )
    except Exception as e:  # noqa: BLE001
        print(f"WARNING: Could not load assets: {e}")
        return None, None, None


model, feature_cols, workout_summary = _load_assets()


# ── Auth dependencies ──────────────────────────────────────────────────────────


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


# ── Endpoints ──────────────────────────────────────────────────────────────────


@app.post("/train")
async def train_model(
    file: UploadFile = File(...),
    uid: str = Depends(require_premium),
):
    """Retrain the XGBoost model with an uploaded FitNotes CSV (premium only)."""
    if not file.filename.endswith(".csv"):
        raise HTTPException(
            status_code=400, detail="Only CSV files are allowed."
        )
    try:
        run_pipeline(file.file)
        global model, feature_cols, workout_summary  # noqa: PLW0603
        model, feature_cols, workout_summary = _load_assets()
        return {"message": "Model successfully trained and updated!"}
    except Exception as exc:
        raise HTTPException(
            status_code=500, detail=f"Training error: {str(exc)}"
        ) from exc


@app.get("/exercises")
def get_exercises():
    """Return all known exercises grouped by category (public endpoint)."""
    try:
        return (
            workout_summary
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
    """Invert the Epley formula to get a working weight for a target rep count."""
    return one_rm / (1 + 0.0333 * reps)


@app.post("/recommend")
def get_recommendation(
    req: WorkoutRequest,
    uid: str = Depends(get_uid),
):
    """Return an AI recommendation for the requested exercise (auth required)."""
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
        if pred_1rm < required_1rm * threshold:
            target_w = round(_get_weight(pred_1rm, target_r) / 2.5) * 2.5
            status = "AI OVERRIDE: Fatigue detected - weight adjusted for safety"
        else:
            status = base_status

    insights = []
    if had_form:
        insights.append(
            "Form issues were logged last session"
            " - prioritize technique over load today."
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
            "Strong momentum - your 1RM has been climbing consistently. Keep it up."
        )

    return {
        "target_reps": int(target_r),
        "target_weight": float(target_w),
        "status": status,
        "predicted_1rm": pred_1rm,
        "required_1rm": required_1rm,
        "notes_insight": " ".join(insights),
    }

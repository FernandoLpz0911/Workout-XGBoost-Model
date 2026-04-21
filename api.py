from fastapi import FastAPI, HTTPException, UploadFile, File
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel
import pandas as pd
import joblib
from pipeline import run_pipeline
import os

app = FastAPI(title="AI Workout API")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["*"], 
    allow_headers=["*"],
)
@app.post("/train")
async def train_model(file: UploadFile = File(...)):
    if not file.filename.endswith('.csv'):
        raise HTTPException(status_code=400, detail="Only CSV files are allowed.")
    
    try:
        # Pass the file-like object directly to your pipeline
        run_pipeline(file.file)
        
        # Reload the newly trained assets into global variables so the API uses them immediately
        global model, feature_cols, workout_summary
        model = joblib.load('xgb_model.joblib')
        feature_cols = joblib.load('feature_cols.joblib')
        workout_summary = pd.read_csv('Processed_Workout_Data.csv', parse_dates=['Date'])
        
        return {"message": "Model successfully trained and updated!"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error during training: {str(e)}")

# Load assets
try:
    model = joblib.load('xgb_model.joblib')
    feature_cols = joblib.load('feature_cols.joblib')
    workout_summary = pd.read_csv('Processed_Workout_Data.csv', parse_dates=['Date'])
except Exception as e:
    print(f"WARNING: Could not load assets: {e}")
    model = None
    feature_cols = None
    workout_summary = None

def get_weight(one_rm, reps): 
    return one_rm / (1 + 0.0333 * reps)

# --- 2. Define Data Models ---
class WorkoutRequest(BaseModel):
    category: str
    exercise: str


@app.get("/exercises")
def get_exercises():
    # Group the dataframe by category and get unique exercises
    # This automatically updates whenever your CSV updates!
    try:
        workout_map = workout_summary.groupby('Category')['Exercise'].unique().apply(list).to_dict()
        return workout_map
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Error reading exercise data: {str(e)}")

# --- 3. API Endpoint ---
@app.post("/recommend")
def get_recommendation(req: WorkoutRequest):
    ex_data = workout_summary[workout_summary['Exercise'] == req.exercise]
    
    if ex_data.empty:
        raise HTTPException(status_code=404, detail="No data found for this exercise.")
        
    # Safely extract and cast all historical values to floats
    last_session = ex_data.iloc[-1]
    last_1rm = float(last_session['Session_Max_1RM'])
    last_days = float(last_session['Days_Since_Last'])
    last_w = float(last_session['Max_Weight'])
    last_reps = float(last_session['Avg_Reps'])
    last_volume = float(last_session['Volume_Load']) 
    
    # 1. Setup simulation input using a dictionary to guarantee structure
    input_data = {col: [0.0] for col in feature_cols}
    sim_input = pd.DataFrame(input_data)
    
    # 2. Inject current state
    sim_input.at[0, 'Days_Since_Last'] = last_days
    sim_input.at[0, 'Previous_1RM'] = last_1rm
    sim_input.at[0, 'Prev_Volume_Load'] = last_volume 
    
    if f'Exercise_{req.exercise}' in feature_cols: 
        sim_input.at[0, f'Exercise_{req.exercise}'] = 1.0
    if f'Category_{req.category}' in feature_cols: 
        sim_input.at[0, f'Category_{req.category}'] = 1.0

    # 3. FORCE exact column order to satisfy XGBoost
    sim_input = sim_input[feature_cols].astype(float)
    
    # 4. Predict
    pred_1rm = float(model.predict(sim_input)[0])
    
    # --- YOUR AI VALIDATION LOGIC ---
    override_thresholds = {'Legs': 0.95, 'Chest': 0.95, 'Back': 0.95, 'Shoulders': 0.90, 'Arms': 0.85}
    cat_threshold = override_thresholds.get(req.category, 0.95)

    if last_reps >= 10:
        target_w = last_w + 2.5
        target_r = 8
        base_status = "PROGRESSION: Weight Increased"
    elif last_reps < 6:
        target_w = last_w
        target_r = 8
        base_status = "STABILIZATION: Form Focus"
    else:
        target_w = last_w
        target_r = 10
        base_status = "VOLUME: Pushing for Graduation"

    if target_w == 0: 
        target_w = round(get_weight(pred_1rm, 8) / 2.5) * 2.5
        target_r = 8
        status = "NEW EXERCISE: Baseline"
    else:
        required_1rm = target_w * (1 + 0.0333 * target_r)
        if pred_1rm < (required_1rm * cat_threshold):
            target_w = round(get_weight(pred_1rm, target_r) / 2.5) * 2.5
            status = "AI OVERRIDE: Fatigue Detected. Adjusted for safety."
        else:
            status = base_status

    return {
        "target_reps": int(target_r),
        "target_weight": float(target_w),
        "status": status,
        "predicted_1rm": float(pred_1rm),
        "required_1rm": float(required_1rm) if 'required_1rm' in locals() else 0.0
    }
import pandas as pd
import numpy as np
import xgboost as xgb
import joblib

def calculate_hybrid_1rm(weight, reps):
    if reps <= 0: return 0
    if reps <= 6: return weight / (1.0278 - 0.0278 * reps) # Brzycki
    elif reps <= 11: return weight * (1 + 0.0333 * reps) # Epley
    else: return (100 * weight) / (52.2 + 41.9 * np.exp(-0.055 * reps)) # Mayhew

# NEW: Pass 'uploaded_file' into the function
def run_pipeline(uploaded_file):
    print("Starting data processing and model training pipeline...")
    
    # 1. Load Data dynamically from the uploader
    df = pd.read_csv(uploaded_file)
    df.columns = df.columns.str.strip()
    
    # 2. Clean and Filter Working Sets
    df_clean = df.dropna(subset=['Weight', 'Reps']).copy()
    df_clean['Date'] = pd.to_datetime(df_clean['Date'])
    df_clean['Estimated_1RM'] = df_clean.apply(lambda x: calculate_hybrid_1rm(x['Weight'], x['Reps']), axis=1)
    
    idx = df_clean.groupby(['Date', 'Exercise'])['Weight'].transform('max') == df_clean['Weight']
    working_sets = df_clean[idx]
    
    # 3. Group and Feature Engineer
    workout_summary = working_sets.groupby(['Date', 'Exercise', 'Category']).agg(
        Sets=('Reps', 'count'),
        Avg_Reps=('Reps', 'mean'),
        Max_Weight=('Weight', 'max'),
        Session_Max_1RM=('Estimated_1RM', 'max')
    ).reset_index()
    
    workout_summary['Volume_Load'] = workout_summary['Sets'] * workout_summary['Avg_Reps'] * workout_summary['Max_Weight']
    
    workout_summary = workout_summary.sort_values(by=['Exercise', 'Date'])
    workout_summary['Days_Since_Last'] = workout_summary.groupby('Exercise')['Date'].diff().dt.days.fillna(14)
    workout_summary['Previous_1RM'] = workout_summary.groupby('Exercise')['Session_Max_1RM'].shift().fillna(workout_summary['Session_Max_1RM'])
    workout_summary['Last_Avg_Reps'] = workout_summary.groupby('Exercise')['Avg_Reps'].shift().fillna(workout_summary['Avg_Reps'])
    workout_summary['Prev_Volume_Load'] = workout_summary.groupby('Exercise')['Volume_Load'].shift().fillna(workout_summary['Volume_Load'])
    
    # 4. Train the Model
    df_encoded = pd.get_dummies(workout_summary, columns=['Exercise', 'Category'])
    features_to_drop = ['Date', 'Max_Weight', 'Session_Max_1RM', 'Last_Avg_Reps', 'Avg_Reps', 'Sets', 'Volume_Load']
    X = df_encoded.drop(columns=features_to_drop, errors='ignore')
    y = df_encoded['Session_Max_1RM']
    
    print("Training XGBoost Model...")
    model = xgb.XGBRegressor(n_estimators=100, learning_rate=0.1)
    model.fit(X, y)
    
    # 5. Export Assets
    joblib.dump(model, 'xgb_model.joblib')
    joblib.dump(list(X.columns), 'feature_cols.joblib')
    workout_summary.to_csv('Processed_Workout_Data.csv', index=False)
    
    print("Pipeline complete! Saved model, features, and processed CSV to disk.")
    return True
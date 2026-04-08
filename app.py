import streamlit as st
import pandas as pd
import joblib
from pipeline import run_pipeline

# --- 1. Helper Functions ---
def get_weight(one_rm, reps): 
    return one_rm / (1 + 0.0333 * reps)

# --- 2. Load Pre-trained Assets ---
@st.cache_resource
def load_assets():
    model = joblib.load('xgb_model.joblib')
    feature_cols = joblib.load('feature_cols.joblib')
    workout_summary = pd.read_csv('Processed_Workout_Data.csv', parse_dates=['Date'])
    return model, feature_cols, workout_summary

st.set_page_config(page_title="AI Workout Model", layout="wide")
st.title("Autonomous AI Workout Model")

# Try to load assets
try:
    model, feature_cols, workout_summary = load_assets()
    assets_loaded = True
except FileNotFoundError:
    assets_loaded = False

# --- 3. Sidebar for Data Upload & Retraining ---
with st.sidebar:
    st.header("Update Data")
    uploaded_file = st.file_uploader("Upload FitNotes CSV", type="csv")
    
    if uploaded_file is not None:
        if st.button("Train Model with New Data", type="primary", use_container_width=True):
            with st.spinner("Processing FitNotes data and training XGBoost..."):
                # Pass the uploaded file to the pipeline!
                run_pipeline(uploaded_file)
                st.cache_resource.clear() 
            st.success("Training complete!")
            st.rerun()

# --- 4. User Interface ---
if not assets_loaded:
    st.warning("Model and data assets not found. Please upload your FitNotes CSV in the sidebar to initialize the AI.")
else:
    st.success("Model loaded and ready!")
    
    col1, col2 = st.columns(2)
    
    with col1:
        categories = sorted(workout_summary['Category'].unique())
        selected_cat = st.selectbox("Select Category:", categories)
        
    with col2:
        exercises = sorted(workout_summary[workout_summary['Category'] == selected_cat]['Exercise'].unique())
        selected_ex = st.selectbox("Select Exercise:", exercises)
        
    if st.button("Get Recommendation", type="primary"):
        ex_data = workout_summary[workout_summary['Exercise'] == selected_ex]
        
        if not ex_data.empty:
            last_session = ex_data.iloc[-1]
            last_1rm = last_session['Session_Max_1RM']
            last_days = last_session['Days_Since_Last']
            last_w = last_session['Max_Weight']
            last_reps = last_session['Avg_Reps']
            last_volume = last_session['Volume_Load'] 
            
            # Setup simulation input array
            sim_input = pd.DataFrame(columns=feature_cols)
            sim_input.loc[0] = 0.0 
            
            sim_input.at[0, 'Days_Since_Last'] = last_days
            sim_input.at[0, 'Previous_1RM'] = last_1rm
            sim_input.at[0, 'Prev_Volume_Load'] = last_volume 
            
            if f'Exercise_{selected_ex}' in feature_cols: 
                sim_input.at[0, f'Exercise_{selected_ex}'] = 1.0
            if f'Category_{selected_cat}' in feature_cols: 
                sim_input.at[0, f'Category_{selected_cat}'] = 1.0

            sim_input = sim_input.astype(float)
            pred_1rm = model.predict(sim_input)[0]
            
            # --- THE NEW AI VALIDATION LOGIC ---
            
            # 1. Define Category-Specific Thresholds
            override_thresholds = {
                'Legs': 0.95,      # 5% leniency for heavy compounds
                'Chest': 0.95,
                'Back': 0.95,
                'Shoulders': 0.90, # 10% leniency for smaller muscles
                'Arms': 0.85       # 15% leniency for isolation
            }
            # Default to 0.95 if category isn't in dictionary
            cat_threshold = override_thresholds.get(selected_cat, 0.95)

            # 2. Base Decision Logic (Double Progression)
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

            # 3. Apply the AI Reality Check
            if target_w == 0: 
                target_w = round(get_weight(pred_1rm, 8) / 2.5) * 2.5
                target_r = 8
                status = "NEW EXERCISE: Baseline"
            else:
                # Mathematically, what 1RM is required to hit our Double Progression goal?
                required_1rm = target_w * (1 + 0.0333 * target_r)

                # If XGBoost predicts our capacity is below the required threshold, override!
                if pred_1rm < (required_1rm * cat_threshold):
                    # Recalculate target weight based safely on what the AI predicts
                    target_w = round(get_weight(pred_1rm, target_r) / 2.5) * 2.5
                    status = f"AI OVERRIDE: Fatigue Detected. Adjusted for safety."
                else:
                    status = base_status
                
            # Output Display
            st.divider()
            st.subheader(f"SET GOAL: 3 Sets x {target_r} Reps")
            st.metric(label="Target Weight", value=f"{target_w} lbs")
            st.info(f"STATUS: {status}")
            
            # Show the math for transparency
            with st.expander("View AI Diagnostics"):
                st.write(f"**AI Predicted Capacity (1RM):** {pred_1rm:.1f} lbs")
                st.write(f"**Required Capacity (1RM):** {required_1rm:.1f} lbs")
                st.write(f"**Category Safety Buffer:** {cat_threshold * 100:.0f}%")
            
            st.divider()
            st.subheader("📈 Predicted Growth Trajectory")
            
            with st.spinner("Calculating growth trajectory..."):
                import datetime
                import numpy as np
                
                # 1. Grab history
                history_df = ex_data[['Date', 'Session_Max_1RM']].copy()
                history_df = history_df.rename(columns={'Session_Max_1RM': 'Historical 1RM'})
                history_df.set_index('Date', inplace=True)
                
                # 2. Calculate Linear Trend (The Math)
                # Convert dates to numerical "days since start" so numpy can do math on them
                first_date = ex_data['Date'].min()
                days_since_start = (ex_data['Date'] - first_date).dt.days
                
                # Fit a 1st-degree polynomial (a straight line) to your historic 1RMs
                slope, intercept = np.polyfit(days_since_start, ex_data['Session_Max_1RM'], 1)
                
                # 3. Project 12 weeks (3 Months) into the future
                last_date = ex_data['Date'].max()
                future_dates = [last_date + datetime.timedelta(days=x) for x in range(7, 91, 7)]
                future_days_since_start = [(d - first_date).days for d in future_dates]
                
                # Calculate the predicted 1RM using y = mx + b
                projected_1rms = [slope * x + intercept for x in future_days_since_start]
                
                # 4. Format data for Streamlit
                proj_df = pd.DataFrame({
                    'Date': future_dates,
                    'Projected Trendline': projected_1rms
                })
                proj_df.set_index('Date', inplace=True)
                
                # Combine history and projection into one clean chart
                plot_data = pd.concat([history_df, proj_df])
                
                # 5. Render Interactive Chart
                st.line_chart(plot_data)
                
                if slope > 0:
                    st.caption(f"Estimated Growth Rate: +{slope*7:.1f} lbs to your 1RM every week.")
                else:
                    st.caption("Trendline is currently flat/negative. Focus on consistency to shift the trajectory!")
        else:
            st.warning("No data found for this exercise.")
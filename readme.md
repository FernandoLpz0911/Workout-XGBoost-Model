# Auto Workout Model

An intelligent fitness ecosystem that uses XGBoost Machine Learning to predict strength capacity and provide safety-validated workout recommendations. The project consists of a data processing pipeline, a Streamlit dashboard for interactive use, and a FastAPI backend for external integration.

## System Architecture

The project is structured into three primary components:

1.  **Data Pipeline (`pipeline.py`)**: Processes raw FitNotes CSV exports, performs feature engineering (calculating Volume Load and Days Since Last session), and trains an **XGBoost Regressor** to predict your 1RM (One-Rep Max).
2.  **AI Frontend (`app.py`)**: A Streamlit web interface that allows users to upload new data, visualize their growth trajectory with linear trendlines, and receive real-time workout goals.
3.  **REST API (`api.py`)**: A FastAPI implementation that exposes the model's prediction logic via HTTP endpoints, suitable for mobile app integration.

## Key Features

* **Hybrid 1RM Calculation**: Uses a multi-algorithmic approach (Brzycki, Epley, and Mayhew formulas) depending on the rep range to ensure high accuracy in strength estimation.
* **AI Reality Check (Safety Logic)**:
    * **Double Progression**: Automatically suggests weight increases if you hit volume milestones (e.g., 10+ reps).
    * **Fatigue Detection**: If the XGBoost model predicts your capacity is below a certain threshold (adjusted by muscle group, like 95% for Legs vs. 85% for Arms), the AI overrides the weight increase to prevent injury.
* **Growth Trajectory**: Visualizes historical data alongside a 12-week projected trendline using polynomial regression.
* **Automated Retraining**: The Streamlit sidebar allows for instant model updates whenever a new CSV is uploaded.

## Technical Stack

* **Language**: Python 3.10+
* **Machine Learning**: XGBoost, Scikit-learn, Joblib
* **Data Science**: Pandas, Numpy
* **Web Frameworks**: Streamlit (Dashboard), FastAPI (API)
* **DevOps**: Docker, Uvicorn

## Installation & Setup

### Local Setup
1. **Install Dependencies**:
   ```bash
   pip install -r requirements.txt
   ```
2. **Run the Data Pipeline**:
   Ensure you have a FitNotes CSV named correctly or run the initialization through the Streamlit app.
3. **Launch the Apps**:
   * **Streamlit**: `streamlit run app.py`
   * **FastAPI**: `uvicorn api.py:app --reload`

### Docker Deployment
The project includes a `Dockerfile` configured for containerized environments:
   ```bash
   docker build -t workout-ai .
   docker run -p 8080:8080 workout-ai
   ```

## API Endpoints

* **GET `/exercises`**: Returns a mapped dictionary of all categories and their corresponding exercises found in the processed data.
* **POST `/recommend`**: Accepts a category and exercise name to return a JSON object containing target reps, target weight, and the AI's safety status.

## Testing

The `tests/` directory contains a comprehensive pytest suite covering the ML pipeline and all API endpoints.

### Running the tests

```bash
source workout_ai_env/bin/activate
pytest tests/ -v
```

### Test coverage

**`tests/test_pipeline.py`** — Pure computation, no external dependencies.

| Class | What it covers |
|---|---|
| `TestCalculateHybrid1RM` | All three 1RM formulas (Brzycki 1–6 reps, Epley 7–11, Mayhew 12+), formula boundaries, edge cases (0 and negative reps) |
| `TestTagComment` | All comment patterns (form issues, fatigue, drop sets, warm-ups), case insensitivity, `None`/`NaN`/`pd.NA` inputs, combined flags |
| `TestRunPipeline` | Happy path, missing column errors, too-few-rows error, drop/warmup exclusion, weight-based warmup filter, non-numeric coercion, multi-exercise one-hot encoding, `Days_Since_Last` lag logic, `Volume_Load` calculation |

**`tests/test_api.py`** — FastAPI endpoints with Firebase/GCS mocked (see `conftest.py`).

| Class | What it covers |
|---|---|
| `TestTrainEndpoint` | Non-CSV rejection, oversized file (413), 409 when training already in progress, happy path |
| `TestExercisesEndpoint` | 404 when no model, grouped exercise catalogue when model exists |
| `TestRecommendEndpoint` | 404 cases, response shape and field types, `mode` parameter handling |
| `TestModelCache` | FIFO eviction at capacity, no-op below cap |
| `TestDeleteUserDataEndpoint` | Returns 200, evicts in-process cache |
| `TestRecommendLogic` | Every `/recommend` decision branch: FORM FOCUS, DELOAD (plateau), Hypertrophy/Strength PROGRESSION, STABILIZATION, VOLUME, AI OVERRIDE, NEW EXERCISE, plus all five insight strings (form, fatigue, plateau, declining/rising momentum) |

## Neural Network Concept Notes
*Included in the repository (`Notes.txt`) are foundational concepts regarding deep learning:*
* **Activation Functions**: Uses ReLU to act as an "activation switch," converting negative values to zero to break linearity.
* **Optimization**: Implements the Adam optimizer and Mean Squared Error (MSE) loss function to punish large guessing errors.
* **Overfitting Prevention**: Strategies documented include Dropout layers (randomly turning off 20% of neurons), early stopping, and data diversity.
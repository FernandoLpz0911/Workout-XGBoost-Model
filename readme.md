# RepIQ — AI-Powered Strength Training Coach

[![CI](https://github.com/FernandoLpz0911/workoutNeuralNetwork/actions/workflows/ci.yml/badge.svg)](https://github.com/FernandoLpz0911/workoutNeuralNetwork/actions/workflows/ci.yml)

RepIQ is a privacy-first workout tracking system that gives lifters session-by-session weight and rep recommendations backed by a per-user XGBoost model. It ships as two independent components: a fully offline Flutter mobile app and a Python/FastAPI backend that trains and serves personalised models in the cloud.

---

## What RepIQ Does

Most training apps suggest generic progression rules. RepIQ learns your specific strength curve from your own workout history, then applies a safety-checked decision tree to tell you exactly what weight and rep range to target next session.

**Mobile app (RepIQ for Android)**
- FitNotes-style logging: tap an exercise, enter weight and reps, save the set
- AI recommendations computed on-device from your local history — no internet required
- Progress charts for estimated 1RM, max weight, and volume across any date range
- FitNotes CSV import to seed your history instantly

**Cloud backend (`api.py`)**
- Trains a personal XGBoost regressor from a FitNotes CSV upload
- Returns weight/rep targets through a REST endpoint that any client can consume
- Reads free-text set notes ("too heavy", "grip gave out") to detect form issues and fatigue before suggesting a progression

---

## Why RepIQ Is Useful

| Feature | How it works |
|---|---|
| **Hybrid 1RM estimation** | Automatically selects Brzycki (1–6 reps), Epley (7–11), or Mayhew (12+) for the best accuracy at any rep range |
| **Comment-aware training** | NLP tagging of set notes flags form issues, fatigue, drop sets, and warm-ups, which feed into the model and the deload logic |
| **Six-branch decision tree** | FORM FOCUS → DELOAD → PROGRESSION → STABILIZATION → VOLUME → AI OVERRIDE, in priority order |
| **Safety thresholds by muscle group** | Arms/Shoulders require a higher fraction of predicted capacity before a weight increase is suggested, reflecting injury risk |
| **Plateau detection** | If 1RM hasn't improved by 2.5 lbs over four sessions, the app prescribes an automatic deload to 60% |
| **Rolling momentum** | A 3-session polyfit slope distinguishes real strength trends from session-to-session noise |
| **Local-first mobile** | The Flutter app stores all data in SQLite on the device — no account, no sync, no data collection |

---

## Getting Started

### Prerequisites

- Python 3.10+
- Flutter SDK 3.8+
- A Google Cloud project with Firebase Auth and a GCS bucket (backend only)
- A FitNotes CSV export (optional, for seeding history)

---

### Backend — Local Development

```bash
# 1. Clone the repository
git clone <repo-url>
cd workoutNeuralNetwork

# 2. Create and activate a virtual environment
python -m venv workout_ai_env
source workout_ai_env/bin/activate      # Windows: workout_ai_env\Scripts\activate

# 3. Install dependencies
pip install -r requirements.txt

# 5. Start the API server
uvicorn api:app --reload --port 8080
```

The interactive API docs are available at `http://localhost:8080/docs`.

---

### Backend — Docker

```bash
docker build -t repiq-api .
docker run -p 8080:8080 \
  -e GCS_BUCKET=your-gcs-bucket-name \
  -e GOOGLE_APPLICATION_CREDENTIALS=/run/secrets/sa.json \
  repiq-api
```

---

### Backend — Cloud Run (CI/CD)

The repository includes `cloudbuild.yaml`. Trigger a build with:

```bash
gcloud builds submit --config cloudbuild.yaml \
  --substitutions _IMAGE_NAME=gcr.io/YOUR_PROJECT/repiq-api
```

The pipeline builds the Docker image, pushes it to Container Registry, and deploys it to the `workoutmodel` Cloud Run service in `us-central1`.

---

### Mobile App

```bash
cd app

# Install Flutter dependencies
flutter pub get

# Run on a connected Android device or emulator
flutter run
```

To build a release APK:

```bash
flutter build apk --release
```

---

### API Usage

**1. Train a personal model**

```bash
curl -X POST https://your-api/train \
  -H "Authorization: Bearer <firebase-id-token>" \
  -F "file=@my_fitnotes_export.csv"
```

**2. Get a recommendation**

```bash
curl -X POST https://your-api/recommend \
  -H "Authorization: Bearer <firebase-id-token>" \
  -H "Content-Type: application/json" \
  -d '{"exercise": "Bench Press", "category": "Chest", "mode": "hypertrophy"}'
```

Example response:

```json
{
  "target_reps": 10,
  "target_weight": 137.5,
  "status": "HYPERTROPHY PROGRESSION: Weight Increased",
  "predicted_1rm": 192.4,
  "required_1rm": 183.3,
  "notes_insight": "Strong momentum — 1RM climbing consistently!"
}
```

`mode` accepts `"hypertrophy"` (default) or `"strength"`.

---

## Running the Tests

```bash
source workout_ai_env/bin/activate
pytest tests/ -v
```

The test suite (77 tests) requires no cloud credentials — Firebase and GCS are mocked in `tests/conftest.py`.

| File | Coverage |
|---|---|
| `tests/test_pipeline.py` | 1RM formulas, comment tagging, rolling slope, full `run_pipeline` path |
| `tests/test_api.py` | All endpoints, model cache, every `/recommend` decision branch |

---

## Project Structure

```
workoutNeuralNetwork/
├── api.py              # FastAPI application — all endpoints and recommendation logic
├── pipeline.py         # ML pipeline: CSV parsing, feature engineering, XGBoost training
├── requirements.txt    # Python dependencies
├── Dockerfile          # Container image for Cloud Run
├── cloudbuild.yaml     # GCP CI/CD pipeline
├── tests/
│   ├── conftest.py     # Firebase/GCS mocks shared across the test suite
│   ├── test_api.py     # Endpoint and recommendation-logic tests
│   └── test_pipeline.py# Pipeline unit and integration tests
└── app/                # Flutter mobile application (RepIQ)
    ├── lib/
    │   ├── main.dart
    │   ├── views/      # Log, History, Progress, Settings screens
    │   ├── viewmodels/ # Provider state (LogViewModel)
    │   ├── services/   # SQLite storage, local recommendation engine, rest timer
    │   └── models/     # WorkoutSet, Recommendation data classes
    └── pubspec.yaml
```

**Key dependencies**

| Layer | Library | Purpose |
|---|---|---|
| Backend | `xgboost 2.1.4` | Per-user strength prediction model |
| Backend | `fastapi` + `uvicorn` | REST API and async server |
| Backend | `firebase-admin` | ID token verification |
| Backend | `google-cloud-storage` | Model artifact persistence |
| Mobile | `sqflite` | On-device SQLite workout history |
| Mobile | `provider` | Reactive state management |
| Mobile | `fl_chart` | Progress line charts |
| Mobile | `flutter_local_notifications` | Rest timer alerts |

---

## Where to Get Help

- **Bug reports and feature requests**: open an issue in this repository
- **API reference**: interactive Swagger docs at `/docs` when the server is running
- **FitNotes export**: Settings → Export Data in the FitNotes Android app produces a compatible CSV

---

## Contributing

1. Fork the repository and create a feature branch off `main`.
2. For backend changes, add or update tests in `tests/` and confirm `pytest tests/` passes.
3. For mobile changes, run `flutter analyze` and `flutter test` before opening a pull request.
4. Keep pull requests focused — one feature or fix per PR makes review faster.
5. Open an issue first for significant changes so the approach can be discussed before implementation.

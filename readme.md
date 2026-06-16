# RepIQ — AI-Powered Strength Training Coach

[![CI](https://github.com/FernandoLpz0911/workoutNeuralNetwork/actions/workflows/ci.yml/badge.svg)](https://github.com/FernandoLpz0911/workoutNeuralNetwork/actions/workflows/ci.yml)

RepIQ is a privacy-first workout tracking system that gives lifters session-by-session weight and rep recommendations backed by a per-user XGBoost model. It ships as two independent components: a fully offline Flutter mobile app and a local-first Python/FastAPI backend that trains and serves personalized models from disk — no cloud account, no managed database, no external dependency required to run it.

---

## What RepIQ Does

Most training apps suggest generic progression rules. RepIQ learns your specific strength curve from your own workout history, then applies a safety-checked decision tree to tell you exactly what weight and rep range to target next session.

**Mobile app (RepIQ for Android)**
- FitNotes-style logging: tap an exercise, enter weight and reps, save the set
- AI recommendations computed on-device from your local SQLite history — no internet required
- Progress charts for estimated 1RM, max weight, and volume across any date range
- FitNotes CSV import/export to seed or back up your history

**Local backend (`api.py`)**
- Trains a personal XGBoost regressor from a FitNotes CSV upload
- Persists each user's model and training data under a local `models/` directory (`joblib`) — nothing leaves the machine running the server
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
| **Local-first everywhere** | The Flutter app stores all data in SQLite on-device; the backend stores all models and data on local disk — no account, no sync, no third-party data collection |

---

## Getting Started

### Prerequisites

- Python 3.10+
- Flutter SDK 3.8+
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

# 4. Start the API server
uvicorn api:app --reload --port 8080
```

The interactive API docs are available at `http://localhost:8080/docs`. Trained models and uploaded data are written to a local directory on disk — no cloud credentials needed.

---

### Backend — Docker

```bash
docker build -t repiq-api .
docker run -p 8080:8080 -v repiq-data:/app/models repiq-api
```

The volume mount keeps trained models on the host across container restarts.

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

Every request identifies the caller via the `X-User-ID` header (any stable string you choose to represent a local user — there is no account system).

**1. Train a personal model**

```bash
curl -X POST http://localhost:8080/train \
  -H "X-User-ID: my-local-user" \
  -F "file=@my_fitnotes_export.csv"
```

**2. Get a recommendation**

```bash
curl -X POST http://localhost:8080/recommend \
  -H "X-User-ID: my-local-user" \
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

**3. List trained exercises / delete your data**

```bash
curl -X GET    http://localhost:8080/exercises        -H "X-User-ID: my-local-user"
curl -X DELETE http://localhost:8080/delete-user-data  -H "X-User-ID: my-local-user"
```

---

## Running the Tests

```bash
source workout_ai_env/bin/activate
pip install -r requirements.txt pytest pytest-cov httpx
pytest tests/ -v
```

The full suite runs with 100% coverage and needs no external services — everything is local disk and in-process.

| File | Coverage |
|---|---|
| `tests/test_pipeline.py` | 1RM formulas, comment tagging, rolling slope, full `run_pipeline` path |
| `tests/test_api.py` | All endpoints, model cache, every `/recommend` decision branch |

Flutter tests:

```bash
cd app
flutter test --coverage
```

CI (`.github/workflows/ci.yml`) enforces `ruff format`/`ruff check` and pytest for the backend, and `dart format`/`flutter analyze`/95% line coverage for the app, on every push and pull request to `main`.

---

## Project Structure

```
workoutNeuralNetwork/
├── api.py              # FastAPI application — all endpoints and recommendation logic
├── pipeline.py         # ML pipeline: CSV parsing, feature engineering, XGBoost training
├── requirements.txt    # Python dependencies
├── Dockerfile          # Local container image
├── pyproject.toml      # ruff (lint/format) + pytest configuration
├── tests/
│   ├── test_api.py     # Endpoint and recommendation-logic tests
│   └── test_pipeline.py# Pipeline unit and integration tests
├── .github/workflows/ci.yml  # CI: format, lint, tests for backend + app
└── app/                # Flutter mobile application (RepIQ)
    ├── lib/
    │   ├── main.dart
    │   ├── views/      # Log, History, Progress, Settings, Onboarding, Legal screens
    │   ├── viewmodels/ # Provider state (LogViewModel)
    │   ├── services/   # SQLite storage, local recommendation engine, rest timer, notifications
    │   └── models/     # WorkoutSet, Recommendation data classes
    ├── test/           # Flutter unit tests
    └── pubspec.yaml
```

**Key dependencies**

| Layer | Library | Purpose |
|---|---|---|
| Backend | `xgboost 2.1.4` | Per-user strength prediction model |
| Backend | `fastapi` + `uvicorn` | REST API and async server |
| Backend | `joblib` | Local model persistence |
| Backend | `pandas` / `numpy` / `scikit-learn` | Feature engineering and pipeline utilities |
| Mobile | `sqflite` | On-device SQLite workout history |
| Mobile | `provider` | Reactive state management |
| Mobile | `fl_chart` | Progress line charts |
| Mobile | `flutter_local_notifications` | Rest timer alerts |
| Mobile | `file_picker` | FitNotes CSV import/export |

---

## Where to Get Help

- **Bug reports and feature requests**: open an issue in this repository
- **API reference**: interactive Swagger docs at `/docs` when the server is running
- **FitNotes export**: Settings → Export Data in the FitNotes Android app produces a compatible CSV

---

## Contributing

1. Fork the repository and create a feature branch off `main`.
2. For backend changes, add or update tests in `tests/` and confirm `pytest tests/` passes with full coverage; run `ruff format .` and `ruff check .` before committing.
3. For mobile changes, run `flutter analyze` and `flutter test` before opening a pull request.
4. Keep pull requests focused — one feature or fix per PR makes review faster.
5. Open an issue first for significant changes so the approach can be discussed before implementation.

# RepIQ — Mobile App

The Flutter half of [RepIQ](../readme.md): a fully offline Android strength-training logger with an on-device AI recommendation engine.

---

## What the Project Does

RepIQ replaces generic "add 5 lbs every week" advice with recommendations derived from each user's own lift history. It is a four-tab Android application:

| Tab | Purpose |
|---|---|
| **Log** | Tap an exercise, enter weight/reps (or distance/duration for cardio), save the set |
| **History** | Full set history grouped by date, then by exercise |
| **Progress** | Line charts for estimated 1RM, max weight, or total volume over any date range |
| **Settings** | Local data stats, FitNotes CSV import/export, legal pages, data clear |

All workout data is stored in a local SQLite database on the device. No account, no internet connection, no telemetry.

---

## Why the Project Is Useful

| Feature | Detail |
|---|---|
| **On-device recommendations** | `LocalRecommendationEngine` runs the same hybrid-1RM + six-branch decision-tree logic as the Python backend — fully offline, zero latency |
| **Hybrid 1RM estimation** | Automatically selects Brzycki (1–6 reps), Epley (7–11), or Mayhew (12+) for the most accurate estimate at any rep range |
| **Per-exercise training mode** | Each exercise can be individually set to `strength` or `hypertrophy`; the engine adjusts target rep ranges, increments, and graduation thresholds accordingly |
| **Plateau detection** | If 1RM hasn't improved by 2.5 lbs over four sessions, the engine prescribes a deload to 60% of working weight automatically |
| **Comment-aware logic** | Set notes ("too heavy", "grip gave out", "sloppy") are scanned for form issues and fatigue signals that override progression rules |
| **Rest timer** | Configurable countdown with vibration and sound; fires a local notification when time is up even if the app is backgrounded |
| **FitNotes CSV import/export** | Bring an existing training history in, or export RepIQ data back out, via the device file picker |
| **One-time onboarding** | Flagged in `SharedPreferences` — only shows on first launch, never again |
| **Automatic SQLite migration** | Installs that previously stored sets in a SharedPreferences JSON blob are silently migrated into SQLite on first load |

---

## How Users Can Get Started

### Prerequisites

- Flutter SDK `^3.8.1`
- An Android device or emulator

### Install and run

```bash
# From the repo root
cd app
flutter pub get
flutter run
```

### Build a release APK

```bash
flutter build apk --release
```

The signed APK is output to `build/app/outputs/flutter-apk/app-release.apk`.

### Import existing history

If you have a FitNotes export:

1. Open the app → **Settings** tab
2. Tap **Import CSV**
3. Select your FitNotes `.csv` file — sets are deduplicated on import so re-importing is safe

### Run the tests

```bash
flutter test --coverage
```

CI enforces `dart format`, `flutter analyze --fatal-infos`, and a 95% line-coverage floor on every push and pull request to `main`. See [`../.github/workflows/ci.yml`](../.github/workflows/ci.yml).

### Project structure

```
app/
├── lib/
│   ├── main.dart
│   ├── views/        # LogView, HistoryView, ProgressView, SettingsView,
│   │                 # OnboardingView, LegalView
│   ├── viewmodels/   # LogViewModel — Provider state shared across all views
│   ├── services/     # LocalStorageService (SQLite), LocalRecommendationEngine,
│   │                 # RestTimer, NotificationService
│   └── models/       # WorkoutSet, Recommendation
├── test/             # Unit tests mirroring lib/services/
├── android/          # Native Android project (open in Android Studio for Gradle work)
└── pubspec.yaml
```

**Key dependencies**

| Library | Purpose |
|---|---|
| `sqflite` | On-device SQLite workout history |
| `provider` | Reactive state management (`LogViewModel`) |
| `fl_chart` | Progress line charts |
| `flutter_local_notifications` + `timezone` | Rest-timer end-of-countdown notifications |
| `audioplayers` / `vibration` | In-app rest-timer audio and haptic alerts |
| `file_picker` | FitNotes CSV import/export via device storage |
| `shared_preferences` | Onboarding flag, per-exercise training-mode map |
| `sqflite_common_ffi` *(dev)* | In-memory SQLite for deterministic unit tests |

### Optional: connect the Python backend

The app works standalone. If you also run the [Python backend](../readme.md#backend--local-development), you can upload your CSV to train a personal XGBoost model and receive higher-fidelity predictions via the `/recommend` endpoint.

---

## Where Users Can Get Help

- **Bug reports and feature requests** — open an issue in this repository
- **API reference** — interactive Swagger docs at `http://localhost:8080/docs` when the Python backend is running
- **FitNotes export** — in the FitNotes app: Settings → Export Data produces a compatible CSV file

---

## Who Maintains and Contributes

RepIQ is maintained by [Fernando Lopez](https://github.com/FernandoLpz0911).

Contributions are welcome:

1. Fork the repository and create a feature branch off `main`.
2. Run `flutter analyze` and `flutter test` before opening a pull request; CI will enforce the same checks.
3. Add or update tests in `test/` for any change to `lib/services/` or `lib/viewmodels/`.
4. Keep pull requests focused — one feature or fix per PR makes review faster.
5. Open an issue first for significant changes so the approach can be discussed before implementation.

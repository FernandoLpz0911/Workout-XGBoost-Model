# App: RepIQ (Android)

Start: Wed 2026-10-28 05:17 CDT · End: 06:17 CDT · Breaks: none
Deadlines: Plan 05:30 · Build 05:55 · Verify 06:05 · Freeze 06:17
Submission: none (personal sprint) · Needs: tagged `demo` commit, release appbundle builds · Rules: none
Demo: local install on Android device/emulator; Play Store via `flutter build appbundle` · Team: solo + agents

## Sprint state
- Phase: 6 (frozen, local demo) · Build mode: sequential · Base branch: sprint/refactor (off main)
- Resumed: 2026-10-28 17:09 CDT · End: 17:39 CDT · Deploy deferred
- Merged: T2 dead code, T3 backtest, T4 PR trophy, T5 repeat last workout, History/Calendar set-order + reps-only display fixes
- Verified on SM-G781U (release APK, Oct 17 FitNotes import, 2305 sets): Log, rec card, assisted rec, Repeat Last Workout, PR trophies, History, Calendar, Progress chart, Settings import
- Backtest (Oct 17 export): 468 predictions, 80.3% achieved, 11.8% too aggressive, 7.2 lbs mean abs error
- Cut: T6 appbundle/release signing (later), T7 plate calculator
- Known cosmetic: Progress y-axis min/max labels overlap grid labels; default exercise (Ab Crunch Machine) shows empty 3m chart; Repeat Last Workout skips Sauna
- Next: release keystore + `flutter build appbundle` for Play Store

## Core loop
Lifter opens app at gym → picks exercise → sees weight/rep recommendation → logs sets → next session's recommendation adapts.

## Baseline (found 05:20)
- Flutter app already Android-ready, fully offline (SQLite), recommendation engine runs on-device (`lib/services/local_recommendation_engine.dart`).
- App never calls the Python API. `api.py`, `pipeline.py`, `tests/`, Dockerfile, Python CI = dead for Android.
- Non-Android platform folders: ios, macos, linux, windows, web.
- `flutter analyze` clean, 176 tests pass.
- Has: log, history, calendar, progress charts, body tracker, rest timer, CSV import/export, notes, onboarding.
- Missing vs FitNotes: personal records, routines/templates, copy previous workout, plate calculator, supersets, goals.

## Features
- MUST:
  1. Delete dead code: Python backend + its CI, non-Android platform folders.
  2. Algorithm backtest: replay real history session by session, score recommendation vs what was actually achieved.
  3. Personal records: flag PR sets (heaviest weight / best e1RM per exercise) in log + history.
  4. Copy previous workout into today.
  5. Release appbundle builds.
- NICE: plate calculator, routines/templates, split `log_view.dart` (1323 lines).
- NO: supersets, goals, cloud sync, accounts, iOS/desktop/web, full UI refactor this sprint.

## Flows
- Flow "log": Log tab → add exercise → recommendation card → log set → set saved.
- Flow "PR": log set heavier than all previous for exercise → PR badge shows.
- Flow "copy": empty today → "Copy last workout" → same exercises/sets appear for today.

## Architecture
- Stack: Flutter + provider + sqflite (unchanged).
- Pure logic in `lib/services/*` engine-style static classes; tests in `test/`.
- Scripts: test = `flutter test` · build = `flutter build appbundle`.

## Tasks
| # | Pri | Task | Owns | Done when |
|---|-----|------|------|-----------|
| 1 | MUST | Skeleton | (existing app) | analyze + tests green |
| 2 | MUST | Delete dead code | api.py, pipeline.py, tests/, Docker*, py configs, app/{ios,macos,linux,windows,web}, ci.yml | analyze + tests green, CI only Flutter |
| 3 | MUST | Algorithm backtest | lib/services/backtest.dart, test/services/backtest_test.dart | report on real CSV printed |
| 4 | MUST | Personal records | lib/services/personal_records.dart + badge in log/history | tests + visible badge |
| 5 | MUST | Copy previous workout | log_viewmodel, log_view | tests + button works |
| 6 | MUST | Release appbundle | android/ | `flutter build appbundle` succeeds |
| 7 | NICE | Plate calculator | lib/services/plates.dart + dialog | tests |

Test seams:
- Task 3: `backtest.dart: runBacktest(List<WorkoutSet>) -> BacktestReport`
- Task 4: `personal_records.dart: prSetIds(List<WorkoutSet>) -> Set<id>`
- Task 5: `LogViewModel.copyLastWorkout()`

## Done criteria (demo)
- analyze clean, all tests pass
- Backtest numbers on real history
- Appbundle builds; app runs on device
- Tag `demo`

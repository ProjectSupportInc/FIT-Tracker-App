# FitTracker Flutter — Milestone 1 foundation

This is a **Flutter SDK-only**, feature-organized starter implementation based on
`FitTracker_Milestone1_UI_v4.html`. It is an **overlay for an existing Flutter project**:
there is no platform-generated `android/`, `ios/`, or `pubspec.yaml` in this archive.

## Start in the existing Flutter project

1. Create a Git commit/backup first.
2. Extract the archive and copy its `lib/` directory into the project root,
   replacing the original `lib/main.dart`. Keep your existing `pubspec.yaml`,
   `android/`, `ios/`, and native configuration.
3. Copy all included files under `test/` into your project's `test/`.
4. Run from the Flutter project root:

   ```bash
   flutter pub get
   dart format lib test
   flutter analyze
   flutter test
   flutter run
   ```

   The archive contains a replacement `test/widget_test.dart` that does not
   assume the default Flutter counter app.

## Code boundaries

- `app/` – composition root, theme, dependency injection.
- `core/` – reusable UI components and date formatting.
- `features/auth/` – sign-in view and authentication repository boundary.
- `features/workouts/domain/` – immutable workout models and pure progression rules.
- `features/workouts/data/` – repository interface and in-memory sample data.
- `features/workouts/presentation/` – workout screens and workout ViewModel.
- `features/tracker/` – BLE boundary (`TrackerGateway`) and mock adapter.
- `features/home/`, `features/progress/`, `features/meals/`, `features/profile/` – app tabs.

## Behavior in this baseline

- Login screen visually matches the Google sign-in design, but uses **MockAuthRepository**.
  No Google OAuth or identity verification has been implemented.
- Today's workouts are available any time during today's calendar date.
- Same-day workout order and within-workout exercise order are enforced by `WorkoutPolicy`.
  Unfinished workouts from other days cannot block today's workout.
- Past unfinished workouts are inaccessible; future workouts are not yet available.
- A connected tracker is reused across exercises unless the athlete selects another.
- Calibration profile is keyed by `(deviceId, exerciseType)` and may be skipped.
  Calibration interaction is a UI scaffold, not real sensor calibration.
- Reps continue beyond the target. `Finish Exercise` only enables at/above target;
  stopping early does not mark an exercise complete.
- Progress is reported by **workout and exercise**, never as a summed total of
  unrelated exercise repetitions.
- The theme supports light and dark mode.

## Not implemented (deliberately)

- Real Google Sign-In, OAuth/PKCE, backend token validation, account persistence.
- BLE permissions, scanning, pairing, GATT subscribe/write protocol and reconnection.
- ESP32 sensor algorithm/calibration exchange and firmware confirmation.
- Backend APIs, persistent workout history, offline synchronization and time-zone policy.
- Real meal plans and coach dashboard.

The demo repository is in-memory. Its results and calibration profiles are lost on
app restart. This is intentional to avoid presenting mock persistence as production-ready.

## Production integration boundaries

- Replace `MockAuthRepository` with an authentication adapter using a supported
  Google authentication SDK; verify identity at the backend.
- Replace `MockTrackerGateway` with a BLE adapter using your ESP32 GATT service
  UUIDs, characteristics, notifications, connection state, commands, and errors.
- Replace `DemoWorkoutRepository` with a real repository backed by authenticated
  HTTPS endpoints and durable local cache.
- Define how device-side calibration profiles are stored/synced (per sensor & exercise).
- Add integration/widget tests for BLE disconnects, navigation, recovery, and long sessions.

### API contract sketch for the future backend

```
GET    /api/v1/me/workouts?date=YYYY-MM-DD
GET    /api/v1/me/workouts/{workoutId}
POST   /api/v1/me/workouts/{workoutId}/exercises/{exerciseId}/results
GET    /api/v1/me/progress
```

These are proposed endpoints, not existing server routes.

## Platform

Flutter can target Android and iOS from the shared Dart source. iOS builds require
macOS/Xcode. Keep native mobile platform settings from your original Flutter project.

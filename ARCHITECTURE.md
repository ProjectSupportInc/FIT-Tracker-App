# FitTracker architecture

The real workout path uses these boundaries:

```text
FitTrackerApp / AppServices
  AuthViewModel -> AuthRepository -> MockAuthRepository (Google/backend still pending)
  WorkoutViewModel -> WorkoutPolicy (date, exercise order, target rules)
                   -> WorkoutRepository -> LocalWorkoutRepository
                   -> TrackerGateway -> BleTrackerGateway
                                         -> FlutterBleTransport -> ESP32 BLE
  ThemeViewModel -> light/dark theme
```

`LocalWorkoutRepository` uses private app storage for completed results and a local
starter schedule. Plans have dated IDs and previous plans remain available for
history. No fabricated completion is inserted into the real repository. Real
Google sign-in, coach prescriptions, cloud synchronization and account-specific
storage remain separate work.

`BleTrackerGateway` speaks the firmware's binary v1 protocol over Control, Status
and Telemetry characteristics. It serializes commands and waits for matching
application-level ACKs. `TrackerStatus` exposes actual calibration and sensor
readiness. `MockTrackerGateway` is only available by explicit dependency injection
for tests/demo use; normal app startup selects real BLE.

Setup selects the movement and reads the device's saved profile. Calibration
starts learning on the ESP32; three accepted sensor cycles save a full NVS profile.
Start requires a ready sensor and profile. Live counts arrive by telemetry/status.
Finish stops and confirms the device total before saving. A frozen result allows
storage retries without restarting the tracker. Stop-without-completion saves
nothing. Disconnect preserves the local count but requires explicit recovery and
Resume. Backgrounding pauses counting and cancels active calibration.

Workouts are startable only on their calendar date, with earlier same-day workouts
and earlier exercises completed first. Missed earlier dates never block today.
Reps may exceed the target; completion remains an explicit user action.

See [BLE setup and recovery guide](docs/BLE_WORKOUT_SETUP.md) for the two-project
change map, hardware setup, protocol, limits, and verification commands, and
[beginner guide](docs/BEGINNER_GUIDE.md) for Dart/Flutter concepts.

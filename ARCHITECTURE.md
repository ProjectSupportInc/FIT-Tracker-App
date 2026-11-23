# FitTracker architecture

The real workout path uses these boundaries:

```text
FitTrackerApp / AppServices
  AuthViewModel -> AuthRepository -> MockAuthRepository (Google/backend still pending)
  WorkoutViewModel -> WorkoutPolicy (date, exercise order, target rules)
                   -> WorkoutRepository -> LocalWorkoutRepository
                   -> TrackerGateway -> BleTrackerGateway
                                         -> FlutterBleTransport -> ESP32 BLE
  WorkoutAudio -> Android WorkoutAudio.kt -> offline TTS / tones / audio focus
  ThemeViewModel -> light/dark theme
```

`LocalWorkoutRepository` uses private app storage for completed results and a local
starter schedule. Plans have dated IDs and previous plans remain available for
history. No fabricated completion is inserted into the real repository. Real
Google sign-in, coach prescriptions, cloud synchronization and account-specific
storage remain separate work.

`BleTrackerGateway` speaks the firmware's binary v2 protocol over Control, Status
and Telemetry characteristics. It serializes commands and waits for matching
application-level ACKs. `TrackerStatus` exposes actual calibration and sensor
readiness. `MockTrackerGateway` is only available by explicit dependency injection
for tests/demo use; normal app startup selects real BLE.

Setup selects the movement locally and reads device status. START begins pickup,
settling and three-rep calibration; no NVS exercise profile is used. Template lock
automatically starts normal counting. Firmware success replies follow completion
by both workers; PAUSE/FINISH first drain samples and preserve the final count.

An active-attempt journal is written before START. Boot/session identity and a
wrapping snapshot revision prevent stale packets or a restarted device from being
mistaken for the same set. Brief drops reconnect automatically. Relaunch recovery
verifies identity and requires explicit Resume. Backgrounding requests PAUSE;
firmware contact timeouts cover process death and prolonged radio loss.

History holds individual attempts. Latest completed results still drive the daily
completion rules; interrupted results do not unlock exercises. A repeat has its
own progress, preserving prior completion. Final result and journal updates commit
atomically. A frozen final result can survive a failed save and app restart when
its checkpoint reaches storage. No cloud or device-side rep persistence is implied.

Workouts are startable only on their calendar date, with earlier same-day workouts
and earlier exercises completed first. Missed earlier dates never block today.
Reps may exceed the target; completion remains an explicit user action.

See [BLE setup and recovery guide](docs/BLE_WORKOUT_SETUP.md) for the two-project
change map, hardware setup, protocol, limits, and verification commands, and
[beginner guide](docs/BEGINNER_GUIDE.md) for Dart/Flutter concepts.

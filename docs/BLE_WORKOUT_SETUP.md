# Real BLE workout flow

The app now uses **BleTrackerGateway** and **LocalWorkoutRepository** on normal launches. No mock tracker or timer produces workout repetitions in this path. Tests explicitly inject controlled peripherals. Google sign-in is still the demo identity, and workout prescriptions remain a local starter schedule; there is no coach/backend service yet.

## Running it on your phone and ESP32

1. In `/home/kavindu/fitness-tracker/fit-tracker`, build and flash the **updated firmware**. The older BLE_TEST program advertises the same UUIDs but generates fake counts, so replacing the phone app alone is insufficient.

   ```bash
   cd /home/kavindu/fitness-tracker/fit-tracker
   source /home/kavindu/.espressif/v6.1/esp-idf/export.sh
   idf.py build
   idf.py -p /dev/ttyUSB0 flash monitor
   ```

   Choose your actual serial port. Firmware flashing was not performed as part of this change.

2. Check BNO055 wiring: 3.3 V, GND, SDA **GPIO21**, SCL **GPIO22**, address **0x28** for this ESP32/NodeMCU configuration. The new `FT_I2C_SDA_GPIO` / `FT_I2C_SCL_GPIO` settings are configurable in `idf.py menuconfig` under FIT-Tracker configuration. They replace the old hardcoded GPIO8/9; the non-ESP32 defaults remain 8/9. Match the physical board/wiring before flashing.
3. Install/run the app on an Android phone with Bluetooth LE:

   ```bash
   cd /home/kavindu/fitness-tracker/FIT-Tracker-App
   flutter pub get
   flutter run
   ```

   A debug APK can also be built with `flutter build apk --debug`; its output is `build/app/outputs/flutter-apk/app-debug.apk`. This repository has Android platform configuration, but no iOS project.
4. Sign in, select today's available workout, and open its first unfinished exercise.
5. Scan and grant Nearby devices/Bluetooth permissions. On Android 11 or older, scanning also needs location permission and enabled Location services. Select **FitnessTracker**; the actual device ID distinguishes multiple trackers. Battery percentages are omitted because this firmware does not expose a battery characteristic.
6. Setup selects the matching exercise on the ESP32 and reads its calibration profile. If a valid profile exists for that movement and unchanged mounting, you can reuse it. Otherwise open **Calibrate now → Begin calibration**.
7. Hold the sensor still for about **1.5 seconds**, then perform **three consistent movement cycles**, resting at least roughly **0.7 seconds** between cycles. The screen advances only when the detector accepts each cycle. The firmware stores the full profile in NVS before reporting **Calibration saved**. Tap Done.
8. Start Exercise becomes available only after the device confirms a ready sensor and valid profile. Live counts come from BLE notifications; the status heartbeat also supplies the cumulative total. Pause/resume uses acknowledged commands and preserves the count.
9. Once you reach the target, Finish first stops the tracker and obtains its final count, then saves the completion in the phone's private storage. Extra reps are included. The completion screen offers the next exercise, whose own movement profile is selected using the existing connection.

## Sensor placement matters

The supplied repetition detector was written for **mostly fixed-orientation vertical motion**, such as a weight stack. It rejects mounting rotation above approximately 22 degrees. Six movement IDs select separate calibration profiles; they do not turn this detector into six independently validated exercise-recognition algorithms. An arbitrary wrist placement during curls or push-ups may be rejected. Use a suitable mounting and validate each movement against physical reps; algorithm tuning and measured exercise accuracy require hardware trials.

## What changed in each project

| Flutter file | Responsibility |
| --- | --- |
| `tracker/data/fitness_protocol.dart` | Encodes 8-byte Control commands; validates/decodes 16-byte Status and 12-byte rep packets. |
| `tracker/data/flutter_ble_transport.dart` | Permissions, filtered scanning, service discovery, subscriptions and GATT reads/writes using flutter_blue_plus. |
| `tracker/data/ble_tracker_gateway.dart` | Serializes commands, matches request IDs to ACKs, handles timeouts/disconnections, validates data. |
| `tracker/domain/tracker_status.dart` | Authoritative device state, calibration progress, profile/sensor flags, movement-ID mapping. |
| `workouts/presentation/workout_view_model.dart` | Validates workout order, prepares movement, watches sensor calibration, starts/pauses/stops/saves, reconnects and recovers. |
| `workouts/presentation/exercise_setup_screen.dart` | Real device picker and readiness gates. |
| `workouts/presentation/calibration_screen.dart` | Sensor-driven calibration progress and cancellation; no manual rep counter. |
| `workouts/presentation/live_exercise_screen.dart` | Live reps, pause, finish, disconnect feedback, explicit reconnect and save retry. |
| `workouts/data/local_workout_repository.dart` | Atomic JSON history storage via path_provider; dated workout IDs keep different days separate. |
| `app/fittracker_app.dart` | Selects the real gateway/repository and pauses sessions when the app enters the background. |

Paths in this table are relative to `lib/features/`, except `app/fittracker_app.dart`, which is relative to `lib/`.

Firmware changes are applied in `/home/kavindu/fitness-tracker/fit-tracker`:

- `main/main.c`: replaces BLE_TEST timers with BNO055 acquisition at nominal 50 Hz, real rep telemetry, status heartbeat, full-profile NVS storage and sensor recovery.
- `main/app/fitness_session/fitness_session.{c,h}`: new testable command/session state machine connecting the existing detector to BLE.
- `main/bno055.c`, `main/Kconfig.projbuild`: configurable I2C pins and reusable initialization handles.
- `main/platform/ble/ble.{c,h}`: disconnect-generation counter detects even brief link interruptions.
- `main/CMakeLists.txt`: compiles the new session module.
- `main/app/fitness_protocol/fitness_protocol.h`: documents movement IDs and FINISH behavior; wire layouts/UUIDs remain v1-compatible.
- `tests/fitness_session_test.c`, `tests/run_host_tests.sh`, protocol test: host checks for real waveform-driven calibration/counting and session behavior.
- `docs/MOBILE_BLE_WORKOUT.md`: complete firmware-side setup and protocol documentation.

The existing detector's algorithm is retained. The BLE runtime does not start the separate Wi-Fi dashboard. The old `ft_test` fake calibration booleans are ignored; full profiles are stored in `ft_profiles` with validation/version/checksum.

## Protocol summary

Service: `12345678-1234-5678-1234-56789abcdef0`.

| Characteristic | UUID suffix | Use |
| --- | --- | --- |
| Telemetry | `...def1` | Notify cumulative rep totals and device uptime. |
| Control | `...def2` | Write with response: select, calibrate, start/resume, pause, finish, status query. |
| Status | `...def3` | Read + notify state, command result, count, sensor/profile flags and calibration progress. |

All multibyte numbers are little-endian. Every command has a nonzero request ID. A GATT write acknowledgement only proves delivery to the BLE stack; the app waits for the matching status response before reporting success. Unsolicited progress uses request ID zero.

Movement IDs: 1 curl, 2 bench press, 3 push-ups, 4 shoulder press, 5 dumbbell row, 6 squat. Packet definitions are mirrored in `fitness_protocol.dart` and firmware `fitness_protocol.h`.

## Recovery behavior and limits

- **Bluetooth off/permission denied/empty scan:** setup shows the error or empty state and allows another scan. No fake devices are substituted.
- **Disconnect during counting:** firmware pauses; phone preserves its last count. Reconnect uses the same peripheral, checks the exercise and nondecreasing count, then leaves counting paused until Resume. It never sends SELECT during recovery because SELECT clears the counter.
- **Firmware reset or incompatible recovered session:** do not silently merge the counts. Stop the exercise and restart. Protocol v1 has no unique workout-session token; recovery checks device/exercise/state/count and cannot prove identity if another client has replaced the session with indistinguishable data. Use one phone per tracker.
- **Lost command ACK:** disconnect instead of blindly retrying a potentially executed START. Reconnect/restart as directed. If FINISH reached the device but its ACK was lost, the ready device is conservatively treated as an unrecoverable active session; no unverified completion is saved.
- **Cancel calibration/back/background/disconnect:** learning is ended; the firmware restores any prior durable profile. A failed/canceled attempt is not evidence of a newly saved calibration.
- **Sensor failure:** firmware pauses counting, reports sensor-not-ready and retries initialization after sustained unusable readings. Check sensor wiring/power/mounting. Sensor recovery does not automatically resume counting.
- **App backgrounded:** active counting is paused after any pending command finishes; calibration is canceled. No foreground/background tracking service is implemented. If the app is killed, BLE disconnect pauses the firmware; unfinished phone sessions are not restored after process death.
- **Storage failure after confirmed FINISH:** the phone keeps a frozen pending result in memory. Retry saving writes that exact final total without restarting counting. Keep the app open until saving succeeds; a pending result is not durable until the write succeeds.
- **Stop without completing:** no result is written. Offline stop discards the phone session; the disconnected firmware is already paused.
- **Completed results:** stored in `workouts-v1.json` under application support storage; temporary write + rename prevents a partial JSON file. No cloud sync or account-specific backend exists. Corrupt history is reported rather than silently erased.

## Validation

```bash
# Flutter project
flutter analyze
flutter test
flutter build apk --debug

# Firmware project
bash tests/run_host_tests.sh
source /home/kavindu/.espressif/v6.1/esp-idf/export.sh
idf.py build
```

Automated tests use controlled BLE packets and IMU waveforms. Physical BLE permissions/range, BNO055 wiring, flash installation, and rep accuracy still need validation with your phone and board. Verify no movement gives no reps, three real calibration cycles enable Start, pause preserves count, Finish records the final count, profile reuse survives board restart, results survive app restart, and disconnect/cancel paths behave as described above.

Library behavior was checked against the installed plugin sources and [flutter_blue_plus 1.36.8 documentation](https://pub.dev/packages/flutter_blue_plus/versions/1.36.8).

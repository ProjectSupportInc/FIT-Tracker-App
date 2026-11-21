# FreeRTOS BLE workout flow

The app targets the firmware working tree on `feature/port-to-freeRTOS` in
`/home/kavindu/fitness-tracker/fit-tracker`. Mobile changes are on
`feature/implement-use-cases-with-new-esp32-firmware`.

**Three approved firmware corrections are applied:** command request IDs, RESUME
decoding, and the calibration-rep-2 event. No firmware was flashed. The original
firmware remains in use by choice; task-coordination changes are deferred. See the
[firmware review and proposed fixes](FREERTOS_FIRMWARE_REVIEW.md) for the remaining
issues. The unapplied proposal is backed up locally in
`local-reviews/freertos-task-coordination-proposal.tar.gz` (ignored by Git).

Normal launches use `BleTrackerGateway`, `FlutterBleTransport`, and
`LocalWorkoutRepository`. No timer generates reps. Test doubles are explicitly
injected. Sign-in is still a demo identity and prescriptions are a local schedule.

## Using the app

1. Use the current FreeRTOS firmware; the deferred proposal is not required by
   these UI changes.
   Check its own board configuration for I2C pins and BNO055 address; this app does
   not configure wiring. Firmware initialization currently stops before BLE if
   the sensor cannot initialize, so check the serial log if no device advertises.
2. Run `flutter pub get` and `flutter run` in this repository on an Android phone.
   This repository has Android platform configuration, but no iOS project.
3. Select an available workout and exercise. Scanning starts automatically unless
   a tracker is already connected. Grant Bluetooth/Nearby devices access and
   select **FitnessTracker**. The screen advances to the ready view after
   connection. On older Android versions, scanning also
   needs location permission and enabled Location services. Actual device IDs
   distinguish trackers; the firmware has no battery characteristic.
4. Press **Start Exercise**. This starts a new device session, replacing an
   unfinished one if present. Exercise selection stays on the phone.
5. Follow the current prompt on the live screen: move the equipment into position (**WAIT_PICKUP**),
   hold still (**SETTLING**, approximately 1.1 seconds after activity settles),
   then perform three consistent repetitions with a short rest between them
   (**CALIBRATING**). Keep the sensor attached to the same moving equipment.
   Movement/hold animations and three calibration checkpoints follow tracker
   events. They never advance a stage or invent reps. Reduced-motion settings
   disable the animations; text and checkpoints remain available.
6. **RUNNING** begins automatically when the firmware locks its template. Those
   three calibration reps are included in the total. No second START is sent.
   There are no saved per-exercise calibration profiles in this firmware.
7. Pause/resume uses separate commands and confirmed device states. Pausing before
   template lock causes preparation to restart on resume. Pausing after template
   lock preserves the learned movement and total.
8. At the target, **Finish Exercise** obtains a FINISHED snapshot and saves the
   reported total, including extra reps, in private phone storage. It cannot
   recover a rep that the firmware itself drops; see the final-count race in the
   review. The next exercise learns a fresh template using the same connection.

## Code map

Paths below are relative to `lib/features/`.

| File | Responsibility |
| --- | --- |
| `tracker/data/fitness_protocol.dart` | Exact 8-byte command, status and telemetry layouts; opcodes and validation. |
| `tracker/domain/tracker_status.dart` | Eight firmware states, nine events and observed calibration progress. |
| `tracker/data/flutter_ble_transport.dart` | Permissions, service filtering, subscriptions before commands, reads and writes. |
| `tracker/data/ble_tracker_gateway.dart` | Serial commands, unique request IDs, matching replies, heartbeat/progress handling, disconnect errors. |
| `workouts/presentation/workout_view_model.dart` | Local exercise association, preparation/start, pause/reconnect/stop, final-count validation and storage retries. |
| `workouts/presentation/exercise_setup_screen.dart` | Automatic scan, device picker, and connected/start view. |
| `workouts/presentation/live_exercise_screen.dart` | Pickup/hold/calibration guidance and live count controls in one route. Replaces the separate calibration screen. |
| `workouts/presentation/workout_stage_view.dart` | Current-stage prompts, motion cues, calibration checkpoints and animated real rep count. |
| `workouts/data/local_workout_repository.dart` | Durable results and dated workout IDs. |

## Wire contract

Service `12345678-1234-5678-1234-56789abcdef0`; telemetry, control, and status use
suffixes `...def1`, `...def2`, `...def3`. All multi-byte fields are little endian.
The firmware still declares version **1**, but this is incompatible with the old
16-byte status / 12-byte telemetry protocol. The app rejects those old packets.

| Packet | Byte offsets |
| --- | --- |
| Control, 8 bytes | 0 version; 1 command; 2–3 request ID; 4–7 reserved, all zero |
| Status, 8 bytes | 0 version; 1 state; 2 event; 3 detail; 4–5 request ID; 6–7 total reps |
| Telemetry, 8 bytes | 0 version; 1 event type (=1); 2–3 total reps; 4–7 uptime in milliseconds |

Commands: START=1, PAUSE=2, RESUME=3, RESET=4, FINISH=5, GET_STATUS=6.
States: IDLE=0, WAIT_PICKUP=1, SETTLING=2, CALIBRATING=3, RUNNING=4, PAUSED=5,
FINISHED=6, ERROR=7.

Events: NONE=0, COMMAND_OK=1, COMMAND_REJECTED=2, HANDLING_DETECTED=3,
HOLD_COMPLETE=4, CAL_REP=5, CAL_RESET=6, TEMPLATE_LOCKED=7, SENSOR_ERROR=8.
CAL_REP detail is 1/2/3; COMMAND_REJECTED detail is INVALID_STATE=1, BUSY=2,
INTERNAL_ERROR=3. Other details are not interpreted as result codes.

Every command has a nonzero request ID. Mutations require a matching COMMAND_OK
or COMMAND_REJECTED reply; GET_STATUS expects NONE or COMMAND_REJECTED with its
request ID. Request ID zero updates the UI but never completes a command.
A successful Bluetooth write alone is insufficient. Current firmware acknowledges
worker dispatch, not worker completion; that limitation needs the firmware fix.

## Recovery and limits

- Status heartbeats (2 seconds) preserve observed calibration progress; they do
  not carry a calibration count. A reconnect or missed progress event cannot
  recover the exact intermediate number. RUNNING confirms all three were accepted.
  CAL_RESET clears progress. Telemetry heartbeats (1 second) recover cumulative
  totals while running/paused. No telemetry creates a synthetic rep.
- Disconnect does **not** pause this firmware. The phone preserves its last known
  count and warns that the tracker may still run. Reconnect checks the same device,
  state and nondecreasing total, then explicitly pauses active preparation/counting.
  A recovered FINISHED session can be saved if it meets the target.
- There is no device session token or exercise ID. State/count checks cannot prove
  identity after another client replaces a session with indistinguishable data.
  Use one phone per tracker. IDLE or a decreased total is rejected as a reset.
- A missing reply or failed write leaves the outcome uncertain. The app closes
  that connection and requires recovery; it never blindly repeats START or treats
  an unsolicited heartbeat as confirmation. Wrong-ID success replies produce a
  specific firmware diagnostic. Do not work around this by reusing command IDs.
- FINISH is not idempotent in this firmware. The app queries before stopping and
  does not send FINISH again to an already FINISHED/IDLE device. IDLE cannot be
  saved as a completed workout. ERROR requires RESET before a fresh START.
- Backgrounding explicitly pauses an active session after any pending command.
  It does not automatically resume. Force-killing the phone app may leave the
  firmware running; no background service or process-death session restoration is
  implemented.
- Stop without completing writes no result. Offline stop only discards the phone
  session; the dialog explains that reconnecting or powering off is needed to
  stop the physical tracker. A new session resets an abandoned active session.
- A storage failure after FINISHED keeps a frozen result in memory. Retry saves
  the same total without restarting counting. Keep the app open until it succeeds.
- Results use `workouts-v1.json` in application support storage, with atomic file
  replacement. No cloud sync or account-specific backend is implemented.

## Validation

Run `flutter analyze`, `flutter test`, and `flutter build apk --debug`.
The APK is `build/app/outputs/flutter-apk/app-debug.apk`.

Tests cover byte layouts, command/reply correlation, known firmware failures,
preparation, calibration, pause/resume, reconnect, cancellation, final totals,
storage retries and the full screen flow. A temporary C host harness confirmed
that the protocol test fixtures match the real firmware encoders and reproduced
several review findings without changing firmware files.

Hardware validation remains necessary after firmware fixes: check no movement
produces no reps, pickup/hold/calibration transitions, three initial reps, pause
and resume during preparation and counting, BLE disconnect/reconnect, concurrent
FINISH/rep events, sensor loss, app backgrounding, and saved history after restart.

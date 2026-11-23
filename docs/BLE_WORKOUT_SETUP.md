# FreeRTOS BLE workout flow

The firmware is in `/home/kavindu/fitness-tracker/fit-tracker`, branch
`feature/port-to-freeRTOS`. The app branch is
`feature/implement-use-cases-with-new-esp32-firmware`.

Both repositories preserve the previous working pair under tag
`tested-integration-2026-11-21`: **firmware `6eabe43`, mobile `6c3ca04`**.
The user reported basic integration working on that pair; it was not thoroughly
hardware-tested. The changes after those checkpoints use **protocol version 2**.
**Install the new app and firmware together.** Old packet formats are rejected.

The previously deferred worker-coordination proposal is now applied, with its
host tests. The original archive is retained unchanged in the app's ignored
`local-reviews/freertos-task-coordination-proposal.tar.gz`.

Normal launches use real BLE and `LocalWorkoutRepository`. No timer creates reps.
Authentication and prescribed workouts remain demo/local features; results are
stored locally and are not separated by signed-in account or synced to a server.

## Using the app

1. Build the firmware with your existing board and `sdkconfig` settings. See its
   README for BNO055 wiring, NimBLE and FreeRTOS settings. Sensor initialization
   failure prevents advertising; check the serial log if no tracker appears.
2. Run `flutter pub get` and `flutter run` on Android. This checkout has no iOS
   project. Allow Bluetooth/Nearby devices permissions. Older Android versions
   also require Location permission/services for scanning.
3. Select today's available workout and exercise. Scanning starts automatically;
   choose your tracker. The connected view then offers **Start Exercise**.
   An unfinished device session with no local recovery record requires confirmation
   before replacement. Selecting a movement remains a phone-side operation.
4. Follow the live prompt: take your starting position, hold it while movement
   settles, then perform three consistent reps with a brief pause between them.
   The animations illustrate the prompt; real device events advance the stages.
   Reduced-motion settings disable repeating motion.
5. The learned template starts normal counting automatically. The three accepted
   calibration reps are part of the total. Pause/resume before template lock
   restarts preparation; after template lock it retains the template and count.
6. At the target, **Finish Exercise** waits for both firmware workers to stop and
   drain samples, then saves the final count, including extra reps. The next
   exercise learns a new template on the same connection.

### Repeat an exercise or workout

Completed items stay grey and keep their checkmarks. Tap a completed exercise to
see its results, then use the options menu's **Repeat exercise** action. Workout
options offer **View history** and **Repeat workout**. A confirmation sheet explains
that the previous results remain saved before creating a new attempt.

Repeats are available for today. A whole-workout repeat has independent progress;
it does not clear the day's completion or lock other completed exercises again.
The workout details screen lets you continue or end a pending repeat. History
retains every completed attempt and any interrupted attempt the user chose to keep.

### Hands-free calibration restart and audio

After an incorrect first or second calibration candidate, return the equipment
to rest and leave it still for **eight seconds**. Continuous quiet clears unfinished
calibration and returns to pickup. Any new movement restarts the quiet timer.
Long rests during calibration also trigger this reset; normal tracking reps are
never cleared by this gesture. If three candidates have already locked a wrong
template, stop and restart the exercise through the app.

The volume/help icon in setup/live and **Profile → Workout guidance** offer voice
and tones, tones only, mute, optional spoken counts, and a test sound. Android uses
an installed offline English TTS voice; otherwise it plays short tones. Use media
volume or connected headphones. New guidance replaces obsolete speech, heartbeats
do not replay prompts, and audio stops in the background. The screen stays awake
only while the live workout is visible. Calls/audio focus can interrupt guidance.

Keep the BNO055 attached to the same moving weight/equipment. Push-ups now have
an appropriate illustration, but a stationary machine-mounted tracker cannot
measure body-only movement. Body mounting and each exercise's accuracy still need
physical validation; illustrations do not add a new detection algorithm.

## Recovery behavior

The app stores the device ID, boot ID, session ID, attempt ID, last confirmed reps,
and repeat progress before START and as the set advances. Results and journal
changes use one serialized, flushed, atomic file replacement. Earlier version-1
history migrates into the version-2 schema in the same `workouts-v1.json` file.
The Git checkpoint restores code, not phone storage; the older app cannot read
the migrated version-2 file.

| Failure | Firmware behavior | App behavior |
| --- | --- | --- |
| Brief BLE drop while counting | Keeps counting until ten seconds have elapsed since the last valid phone contact. | Retries the same device after 1, 2, 4, then 8 seconds; restores matching cumulative reps without another START. |
| Link lost during preparation | Pauses on disconnect/unsubscription, or after six seconds without valid contact. | Requires Resume if the device paused; preparation then restarts. |
| Long link loss | Coordinates PAUSE after ten seconds without valid contact; preserves count/template. | Keeps confirmed reps; offers manual reconnect when bounded automatic retries end. |
| App killed/restarted | Contact timeout pauses the device even if BLE disconnect is delayed. | Restores the local attempt. Open workout reconnects, verifies identity, and pauses any still-active set; Resume is explicit. |
| ESP32 reboot or replacement session | New boot ID or session ID prevents old mutations. Volatile reps/template are lost on reboot. | Rejects mismatched recovery, offers **Keep recorded reps and end**, then a new attempt. Never resets another session during recovery. |
| Sensor/worker failure | Invalid samples and stalled progress cause coordinated recovery and ERROR. Unconfirmed stopping latches ERROR until reboot. | Preserves confirmed count and shows interruption instead of claiming completion. |
| Command manager hangs | Platform task watchdog is configured for an eight-second timeout. | Missing fresh responses disconnect the transport and trigger recovery. A reboot is detected by boot ID. |
| App backgrounded/phone locked | Receives PAUSE when possible; contact timeout covers failed delivery. | Stops audio and reconnect attempts; returning does not automatically Resume a paused set. |
| Lost START/FINISH reply | Request/session checks prevent applying a command to the wrong set; retries of settled actions are idempotent. | Reconnects and queries actual state. An uncertain START keeps its durable record; a matching FINISHED total can be saved. |
| Failed result save | Device remains stopped. | Retains the frozen result and retries the same attempt ID. If the recovery journal was written, a new app process can finish saving it. |

GET_STATUS runs every two seconds and renews contact only for matching boot/session
IDs. Incoming status/telemetry freshness is monitored; six seconds without a fresh
packet causes disconnect on the next poll. Firmware deadlines are checked by the
manager loop, so actual timing includes scheduler/wakeup delay. The ten-second
counting grace is measured from last contact, not exactly from radio loss.

Offline stop does not prove the sensor stopped. The device contact timeout provides
an automatic pause; reconnect or power off to confirm it. Keeping an interrupted
result records only confirmed reps and does not mark the exercise complete. Storage
failure can prevent the latest checkpoint from reaching disk; no implementation
can recover sensor reps lost in a reboot before they were reported to the phone.

## Wire contract

Service `12345678-1234-5678-1234-56789abcdef0`; telemetry, control and status use
suffixes `...def1`, `...def2`, `...def3`. All multibyte integers are little endian.
The existing three characteristics are unchanged and all values fit the default
20-byte ATT payload.

| Packet | Byte offsets |
| --- | --- |
| Control, 12 bytes | 0 version=2; 1 command; 2–3 request ID; 4–7 boot ID; 8–11 session ID |
| Status, 20 bytes | 0 version=2; 1 state; 2 event; 3 detail; 4–5 request ID; 6–7 reps; 8–11 boot ID; 12–15 session ID; 16–17 revision; 18 calibration count; 19 flags |
| Telemetry, 18 bytes | 0 version=2; 1 type=1; 2–3 reps; 4–7 uptime ms; 8–11 boot ID; 12–15 session ID; 16–17 revision |

Commands: START=1, PAUSE=2, RESUME=3, RESET=4, FINISH=5, GET_STATUS=6.
States: IDLE=0, WAIT_PICKUP=1, SETTLING=2, CALIBRATING=3, RUNNING=4, PAUSED=5,
FINISHED=6, ERROR=7.
Events: NONE=0, COMMAND_OK=1, COMMAND_REJECTED=2, HANDLING_DETECTED=3,
HOLD_COMPLETE=4, CAL_REP=5, CAL_RESET=6, TEMPLATE_LOCKED=7, SENSOR_ERROR=8.

CAL_REP detail is 1/2/3; CAL_RESET detail 1 means inactivity, 0 means rejected
calibration. Rejection details: INVALID_STATE=1, BUSY=2, INTERNAL_ERROR=3,
SESSION_MISMATCH=4. Status flag bit 0 means a worker operation is pending; bit 1
means the last pause was caused by lost contact. Calibration progress is present
in every snapshot, including READ/GET_STATUS and heartbeats.

Boot ID is a nonzero random MCU-start nonce. The phone assigns a new nonzero
session ID per attempt; START establishes it and RESET clears it. Worker messages
use a separate internal generation so delayed samples cannot enter a new set.
A wrapping 16-bit revision orders status and telemetry within one boot.

Request IDs are nonzero for phone commands and must match replies. Request ID 0
is an unsolicited snapshot: it updates the UI but never confirms a phone command.
Success means both workers completed the operation. Bluetooth write success alone
is insufficient. The IDs prevent accidental stale-session actions; they are not
BLE pairing/authentication credentials.

## Code map and validation

- `tracker/data/fitness_protocol.dart`: wire codec and validation.
- `tracker/data/ble_tracker_gateway.dart`: serial commands, reply matching, polling,
  revision ordering, identity binding and transport errors.
- `workouts/presentation/workout_view_model.dart`: session/repeat ownership,
  reconnect policy, lifecycle, final-count validation and persistence.
- `workouts/domain/workout_journal.dart`: durable active-attempt and repeat records.
- `workouts/data/local_workout_repository.dart`: atomic history/journal storage.
- `workouts/presentation/workout_history_screen.dart`: attempt history and repeat flow.
- `workouts/presentation/workout_stage_view.dart` and `exercise_illustration.dart`:
  phase prompts, motion cues and exercise-specific vector drawings.
- `workouts/presentation/workout_audio.dart` and Android `WorkoutAudio.kt`: cue
  selection/settings and native speech, tones, audio focus and screen-awake adapter.

Run `flutter analyze`, `flutter test`, and `flutter build apk --debug`. In the
firmware repository run `bash tests/run.sh` and, with ESP-IDF exported, `idf.py build`.
The app artifact is `build/app/outputs/flutter-apk/app-debug.apk`; firmware output
is in its `build/` directory. The firmware README describes host-test limits.

Before marking this new pair hardware-tested, exercise these cases on equipment:

- Pickup/hold, three consistent reps, extra reps, no-motion/no-false-count behavior.
- Mistaken first/second candidate, eight-second rest, then successful recalibration.
- PAUSE/FINISH at the instant a rep completes or the template locks.
- Brief/long BLE loss; phone force-stop/relaunch; ESP32 reboot; sensor disconnection.
- Resume after preparation versus after template lock; preserve final totals.
- Repeat one exercise and a whole workout; close/reopen the app between exercises.
- Voice/tones/mute, headphones, incoming calls, screen lock and reduced motion.

The new firmware has not been flashed by this work. Automated tests/builds and
rendered UI inspection are separate from radio, sensor and physical rep trials.

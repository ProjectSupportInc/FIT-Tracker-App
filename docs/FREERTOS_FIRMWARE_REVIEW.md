# FreeRTOS firmware integration review

Reviewed the working tree at `/home/kavindu/fitness-tracker/fit-tracker`, branch
`feature/port-to-freeRTOS`, on 2026-11-21, including the user's uncommitted changes.
The initial review was read-only. After explicit approval, only three corrections
were applied: echo request IDs, accept RESUME, and send CAL_REP for calibration
rep 2. Formatting configuration, comments, struct/enum names and all other firmware
files remain unchanged. Nothing was flashed.

Findings 1, 2 and 5 below describe the original defects and are now fixed. Findings
3 and 4 remain unresolved. Mobile tests model the intended replies and also reject
broken replies from older firmware builds.

## 1. Fixed: successful command replies use the wrong request ID

`main/app/app_tasks/command_manager/command_manager.c:213`

`send_status(FT_EVENT_COMMAND_OK, 0, command->command_code)` sends the opcode where
the phone expects its unique request ID. For example START request 42 produces
request ID 1. The action may execute, but the phone cannot confirm it. GET_STATUS
and rejected commands already echo the correct ID.

Applied correction:

```c
send_status(FT_EVENT_COMMAND_OK, 0, command->request_id);
```

Keep distinct IDs per request in the app; accepting any success reply would let
stale replies confirm unrelated actions. The app now reports this mismatch.

## 2. Fixed: RESUME is declared and handled but rejected at the BLE decoder

`main/app/ft_protocol/ft_protocol.c:54`

The valid-command switch omits `FT_CMD_RESUME`. An 8-byte packet
`01 03 2a 00 00 00 00 00` fails decoding, so the BLE callback rejects it before
command-manager or worker handlers can run. The phone cannot resume a paused set.

Applied correction: add `case FT_CMD_RESUME:` alongside START/PAUSE in the switch.
Do not map resume to START; START is invalid in PAUSED and starts a new session.

## 3. High: command/worker event ordering can lose the final rep or a template lock

`main/app/app_tasks/command_manager/command_manager.c:311,416`

The manager handles phone commands before worker events from the same wakeup.
FINISH switches the state to FINISHED, then `handle_worker_events()` consumes the
latest count but only applies REP_COUNTED while RUNNING. Example reproduced:
manager count 7, pending worker count 8, FINISH followed by REP_COUNTED -> the
finished count stays 7 and the pending 8 is consumed. A later GET_STATUS cannot
recover it. PAUSE can similarly omit the latest count until another rep arrives.

A template-lock event racing PAUSE has another consequence: the rep worker has
entered tracking, but the manager discards TEMPLATE_LOCKED while PAUSED. RESUME
restores CALIBRATING even though the worker is tracking. Future REP_COUNTED events
are ignored, leaving the phone stuck on calibration.

Proposed solution: acknowledge PAUSE/FINISH only after workers have applied them.
Have the rep worker return its final count and detector phase as part of completion;
merge that snapshot before publishing PAUSED/FINISHED. Preserve template-lock
state across a concurrent pause. Tag worker events with a session generation so
RESET/START can reject old events. Merely swapping command/event processing order
reduces one race but cannot handle events still in flight on another task/core.

## 4. High: partial command dispatch can leave workers doing different operations

`main/app/app_tasks/command_manager/command_manager.c:170–213`

A command is sent separately with `eSetValueWithoutOverwrite`. If the data task
accepts it and the rep task has a pending notification, the manager enters ERROR
but does not undo or stop the first task. A rapid RESET -> START or FINISH -> START
can hit this because the success reply confirms dispatch before both tasks finish.
A failed START may leave sensor sampling active while the detector is idle, or the
reverse after other commands. The app cannot make dispatch atomic.

Proposed solution: allow one outstanding worker command, collect completion from
both tasks, then publish the command result. Return BUSY before changing either
worker while another operation is pending. If a worker fails, explicitly stop or
reset both and wait for their acknowledgements before publishing a stable ERROR.
Small worker completion messages/queues are sufficient; this does not require
creating tasks for every command.

## 5. Fixed: calibration rep 2 is announced as a reset

`main/app/app_tasks/command_manager/command_manager.c:277`

`CM_EVT_CAL_REP_2` currently sends `FT_EVENT_CAL_RESET, 2, 0`. A correct app clears
progress, so the displayed 1/3 becomes 0/3 even though the detector accepted rep 2.

Applied correction:

```c
send_status(FT_EVENT_CAL_REP, 2, 0);
```

The app follows the event definition rather than silently treating a reset as a
successful rep. A subsequent TEMPLATE_LOCKED still establishes the initial total 3.

## Other findings and behavior to decide

- **No disconnect policy:** `ble_disconnect_generation()` is never consumed by the
  application tasks. Counting continues while disconnected. This is not inherently
  wrong if offline counting is intended; the new app reflects it. If automatic
  pause is intended, send a disconnect event through command manager and stop both
  workers using the same completion mechanism as PAUSE.
- **Session identity is absent:** there is no exercise ID or session token in any
  packet. Reconnection cannot distinguish a replacement session with the same
  state/count. Add a session identifier in a future version if reliable ownership
  and process-death recovery are required.
- **Protocol version reused:** sizes/layouts/opcodes changed while version remains
  1. The app checks packet lengths and rejects the old firmware. Give the new wire
  contract a distinct version or explicit capability handshake before supporting
  multiple firmware generations.
- **Zero gravity silently becomes zero acceleration:**
  `data_processor.c:182` initializes `scalar_proj=0`; `get_scalar_projection3()`
  writes nothing for a zero gravity vector, so `isfinite(0)` accepts an unusable
  sample. `DP_GRAVITY_MIN_MS2` is defined but unused. Check finite vector components
  and gravity norm against that minimum, then report unavailable sensor data or
  wait for fusion readiness rather than feeding zeros into the detector.
- **Progress cannot be recovered by GET_STATUS:** the readable cache/heartbeat
  retains state and total but not CAL_REP details. The app preserves events it saw;
  missed intermediate progress remains unknown. Add a calibration-progress field
  in a versioned status format if exact progress after reconnect is important.

## Verification and limits

A temporary host C harness compiled the actual command/event handler bodies with
stubbed task notifications and BLE output, plus the unchanged real protocol codec.
It reproduced findings 1, 2, 3 (both FINISH and template-lock races), 4 and 5 and verified the exact status
and telemetry bytes used in the Dart tests. This validates the code paths, not the
real-time behavior of a physical FreeRTOS scheduler. The template-lock case models
a worker already tracking while command manager processes PAUSE and TEMPLATE_LOCKED.

The harness was created under `/tmp`, with no build outputs in the firmware repo.
No ESP-IDF build, flash, radio connection or measured rep-accuracy trial was run.
After fixing these issues, test simultaneous command/rep events on hardware and
verify task completion, calibration restart, final counts and disconnect policy.


### Verification after the approved corrections

A fresh host harness compiled the updated command/event handlers and real protocol
codec. All six commands decode, including RESUME; successful replies echo full
16-bit request IDs; calibration rep 2 sends CAL_REP/detail 2, while real CAL_RESET
behavior is preserved. The known FINISH/template-lock races and partial dispatch
were reproduced again and intentionally left unchanged.

A before/after hash comparison covered 54 firmware files/index entries. Only the
two approved C files changed. Their comment text, every header, `.clang-format`
and the Git staging index were verified unchanged. Build outputs stayed in `/tmp`;
no ESP-IDF build or hardware flash was performed.

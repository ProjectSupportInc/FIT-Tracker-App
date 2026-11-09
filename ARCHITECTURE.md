# FitTracker Flutter Architecture — M1

## Boundaries

```
App composition root / dependency injection
  ├─ AuthViewModel ── AuthRepository ── MockAuthRepository (future: Google + backend)
  ├─ WorkoutViewModel ── WorkoutRepository ── DemoWorkoutRepository (future: REST + local cache)
  │                    └─ TrackerGateway ── MockTrackerGateway (future: Flutter BLE adapter)
  ├─ WorkoutPolicy (pure rules + unit tests)
  └─ ThemeViewModel
       └─ Presentation: Today / Workouts / Setup / Calibration / Live / Progress
```

The widgets do not know whether records came from sample data, REST, local
storage or BLE; this is the central design constraint for future modules.

## Functional rules

- The startable set of workouts is restricted to **today**.
- Workouts within that date are unlocked by completion of all earlier same-day
  workouts (regardless of their scheduled hours).
- Past incomplete and future workouts cannot be performed.
- All earlier exercises in a workout must be complete before starting the next.
- Completion is explicitly requested by the athlete and allowed when
  `currentReps >= targetReps`; hitting target must not stop counting.
- Stop-before-finish creates no completion record.
- The BLE connection is a **session-level resource**, not per-exercise.
- Calibration profile keys are `(device ID, exercise kind)` and remain optional.
- Progress is expressed as workouts completed / exercise-level repetitions,
  not one nonsensical mixed total across exercise types.

## Real implementation interfaces

`AuthRepository` provides a signed-in `AppUser`.
`WorkoutRepository` loads plans and persists exercise results.
`TrackerGateway` scans, connects, configures exercise counting,
streams repetition events, pauses/resumes, stops and saves calibration profiles.

## Next engineering tasks

1. Install/run Flutter, check `flutter analyze` and widget tests.
2. Replace fake auth with production Google sign-in + verified backend session.
3. Specify ESP32 BLE GATT service, characteristics and message payload format.
4. Replace mock BLE gateway and add permission/error/disconnect states.
5. Add backend API + durable cache for workouts, results, calibration metadata.
6. Add integration tests for disconnect, reconnect, app suspension and sync.

The `FitTracker_Milestone1_UI_v4.html` source is the design reference, not
embedded in the Flutter app via WebView. The application uses native Flutter
widgets, which supports Android and iOS from one Dart codebase.

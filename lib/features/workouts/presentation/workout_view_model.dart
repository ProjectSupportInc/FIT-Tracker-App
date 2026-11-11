// Coordinates the workout screens, durable results, and the BLE device.
// Device status is authoritative: a successful Bluetooth write alone is not an ACK.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../tracker/data/tracker_gateway.dart';
import '../../tracker/data/fitness_protocol.dart';
import '../../tracker/domain/tracker_device.dart';
import '../../tracker/domain/tracker_status.dart';
import '../data/workout_repository.dart';
import '../domain/workout_models.dart';
import '../domain/workout_policy.dart';

/// Shared controller created by FitTrackerApp and read through AppServices.
class WorkoutViewModel extends ChangeNotifier {
  WorkoutViewModel({
    required WorkoutRepository repository,
    required TrackerGateway tracker,
  })  : _repository = repository,
        _tracker = tracker {
    _statusSubscription = _tracker.statuses
        .listen(_onStatus, onError: (Object error) => _onTrackerError(error));
    _repSubscription = _tracker.repetitionCounts.listen(_onRepetitions,
        onError: (Object error) => _onTrackerError(error));
  }

  final WorkoutRepository _repository;
  final TrackerGateway _tracker;
  final WorkoutPolicy policy = const WorkoutPolicy();
  late final StreamSubscription<TrackerStatus?> _statusSubscription;
  late final StreamSubscription<int> _repSubscription;
  List<WorkoutPlan> _plans = [];
  Map<String, ExerciseResult> _results = {};
  WorkoutPlan? _activeWorkout;
  ExercisePlan? _activeExercise;

  /// Remember the exact peripheral, so reconnect never silently picks a new one.
  TrackerDevice? _sessionDevice;

  /// A device-confirmed final result survives storage failures for an exact retry.
  ExerciseResult? _pendingResult;

  /// Distinguish a newly learned profile from an old profile restored on cancel.
  int? _learningExerciseId;
  int? _completedCalibrationId;
  int _reps = 0;
  bool _running = false;
  bool _paused = false;
  bool _loaded = false;
  bool _busy = false;
  Completer<void>? _operationDone;
  bool _disconnected = false;
  bool _recovering = false;
  bool _sessionInvalid = false;
  bool _disposed = false;
  String? _trackerError;
  String? _deviceError;
  String? _loadError;

  List<WorkoutPlan> get workouts => List.unmodifiable(_plans);
  Map<String, ExerciseResult> get results => Map.unmodifiable(_results);
  TrackerDevice? get connectedDevice => _tracker.connectedDevice;
  TrackerStatus? get trackerStatus => _tracker.status;
  String? get trackerError => _trackerError ?? _deviceError;
  String? get loadError => _loadError;
  bool get isLoaded => _loaded;
  int get liveReps => _reps;
  bool get isRunning => _running;
  bool get isPaused => _paused;
  bool get isTrackerBusy => _busy;
  bool get isDisconnected => _disconnected;
  bool get hasActiveSession => _activeExercise != null;
  bool get hasPendingResult => _pendingResult != null;
  bool get isCalibrating => trackerStatus?.state == TrackerState.calibrating;

  /// Saving a frozen result can be retried even if Bluetooth later disconnects.
  bool get canFinish =>
      !_busy &&
      (_pendingResult != null ||
          (!_disconnected &&
              !_sessionInvalid &&
              connectedDevice != null &&
              _running &&
              _activeExercise != null &&
              policy.targetReached(_activeExercise!, _reps)));

  /// Read the profile flag from the selected device, not a phone-side fake flag.
  bool isCalibrated(ExercisePlan exercise) =>
      connectedDevice != null &&
      trackerStatus?.exerciseId == exerciseIdForKind(exercise.kind) &&
      trackerStatus?.profileAvailable == true;

  bool didCompleteCalibration(ExercisePlan exercise) =>
      _completedCalibrationId == exerciseIdForKind(exercise.kind);

  bool canStartExercise(ExercisePlan exercise) =>
      !_busy &&
      !hasActiveSession &&
      isCalibrated(exercise) &&
      trackerStatus?.sensorReady == true &&
      trackerStatus?.state == TrackerState.ready;

  /// Root startup calls this. Failures remain visible and can be retried.
  Future<void> load() async {
    _loadError = null;
    try {
      _plans = await _repository.fetchWorkouts();
      _results = await _repository.fetchResults();
      _loaded = true;
    } catch (error) {
      _loaded = false;
      _loadError = 'Unable to load your workouts: $error';
    }
    _notify();
  }

  WorkoutAvailability status(WorkoutPlan workout) =>
      policy.availability(workout, _plans, _results, DateTime.now());
  bool workoutComplete(WorkoutPlan workout) =>
      policy.workoutCompleted(workout, _results);
  bool exerciseComplete(WorkoutPlan w, ExercisePlan e) =>
      policy.exerciseCompleted(w, e, _results);
  bool exerciseUnlocked(WorkoutPlan w, ExercisePlan e) =>
      policy.exerciseUnlocked(w, e, _results);
  int doneCount(WorkoutPlan workout) =>
      workout.exercises.where((e) => exerciseComplete(workout, e)).length;
  ExerciseResult? resultFor(WorkoutPlan w, ExercisePlan e) =>
      _results[exerciseKey(w, e)];

  /// Serializes UI operations, including repeated taps during slow BLE ACKs.
  Future<T> _perform<T>(Future<T> Function() operation) async {
    if (_disposed) throw StateError('Workout controller has closed.');
    if (_busy) {
      throw StateError('Please wait for the current device operation.');
    }
    _busy = true;
    _operationDone = Completer<void>();
    _trackerError = null;
    _notify();
    try {
      return await operation();
    } catch (error) {
      _trackerError = error.toString();
      rethrow;
    } finally {
      _busy = false;
      _operationDone?.complete();
      _operationDone = null;
      _notify();
    }
  }

  Future<List<TrackerDevice>> scan() => _perform(() => _tracker.scan());

  Future<void> connect(TrackerDevice device) => _perform(() async {
        if (hasActiveSession) {
          throw StateError(
              'Stop the current exercise before changing devices.');
        }
        await _tracker.connect(device);
        _disconnected = false;
      });

  /// Setup calls SELECT to load this movement's persisted profile on the ESP32.
  Future<void> prepareExercise(ExercisePlan exercise) => _perform(() async {
        if (hasActiveSession) {
          throw StateError('An exercise is already active.');
        }
        if (connectedDevice == null) {
          throw StateError('Connect your tracker first.');
        }
        // A previous app process may have left a paused session on the peripheral.
        // This is a new setup flow, so deliberately end that session before SELECT.
        final state = trackerStatus?.state;
        if (state == TrackerState.paused ||
            state == TrackerState.running ||
            state == TrackerState.calibrating ||
            state == TrackerState.error) {
          await _tracker.stopCounting();
        }
        await _tracker.selectExercise(exerciseKind: exercise.kind);
      });

  Future<void> beginCalibration(ExercisePlan exercise) => _perform(() async {
        if (hasActiveSession) {
          throw StateError('Stop the current exercise before calibrating.');
        }
        if (trackerStatus?.exerciseId != exerciseIdForKind(exercise.kind)) {
          await _tracker.selectExercise(exerciseKind: exercise.kind);
        }
        _learningExerciseId = exerciseIdForKind(exercise.kind);
        _completedCalibrationId = null;
        try {
          await _tracker.beginCalibration(exerciseKind: exercise.kind);
        } catch (_) {
          _learningExerciseId = null;
          rethrow;
        }
      });

  /// FINISH cancels calibration too. Offline cancellation only closes the phone UI;
  /// the firmware independently cancels learning when the BLE link is lost.
  Future<void> cancelCalibration() => _perform(() async {
        _learningExerciseId = null;
        _completedCalibrationId = null;
        if (hasActiveSession) {
          throw StateError('Cannot cancel calibration during an exercise.');
        }
        if (connectedDevice != null) await _tracker.stopCounting();
      });

  Future<void> refreshTrackerStatus() =>
      _perform(() => _tracker.refreshStatus());

  Future<void> startExercise(WorkoutPlan workout, ExercisePlan exercise) async {
    if (!canStartExercise(exercise)) {
      throw StateError(
          'Connect the tracker and complete calibration before starting.');
    }
    await _perform(() async {
      if (status(workout) != WorkoutAvailability.ready ||
          !exerciseUnlocked(workout, exercise) ||
          exerciseComplete(workout, exercise)) {
        throw StateError('This exercise is not available yet.');
      }
      _activeWorkout = workout;
      _activeExercise = exercise;
      _sessionDevice = connectedDevice;
      _reps = 0;
      _pendingResult = null;
      _sessionInvalid = false;
      _disconnected = false;
      try {
        await _tracker.startCounting(exerciseKind: exercise.kind);
        _running = true;
        _paused = false;
      } catch (_) {
        // A timeout does not prove START was rejected. End or disconnect before
        // dropping the local session, so a retry cannot count an unknown session.
        try {
          if (connectedDevice != null) await _tracker.stopCounting();
        } catch (_) {
          await _tracker.disconnect();
        }
        _clearSession();
        rethrow;
      }
    });
  }

  Future<void> togglePause() => _perform(() async {
        if (!_running ||
            _disconnected ||
            _sessionInvalid ||
            _pendingResult != null) {
          throw StateError(
              'Reconnect the active exercise before changing counting.');
        }
        if (_paused) {
          await _tracker.resumeCounting();
        } else {
          await _tracker.pauseCounting();
        }
        // Device status, rather than an optimistic local toggle, drives the label.
        _onStatus(trackerStatus);
      });

  /// Reconnect never SELECTs (which resets reps) and never resumes automatically.
  Future<void> reconnectActiveExercise() => _perform(() async {
        final device = _sessionDevice;
        final exercise = _activeExercise;
        if (device == null || exercise == null || _pendingResult != null) {
          throw StateError('There is no active tracker session to reconnect.');
        }
        _recovering = true;
        try {
          await _tracker.connect(device);
          await _tracker.refreshStatus();
          final restored = trackerStatus;
          if (restored == null ||
              restored.exerciseId != exerciseIdForKind(exercise.kind) ||
              restored.repetitions < _reps ||
              (restored.state != TrackerState.paused &&
                  restored.state != TrackerState.running)) {
            _sessionInvalid = true;
            throw StateError(
                'The tracker session has reset. Stop this exercise and start it again.');
          }
          if (restored.state == TrackerState.running) {
            await _tracker.pauseCounting();
          }
          _reps = trackerStatus!.repetitions;
          _disconnected = false;
          _sessionInvalid = false;
          _running = true;
          _paused = true;
        } finally {
          _recovering = false;
        }
      });

  /// Stop is also allowed offline: the device pauses itself on disconnection.
  Future<void> stopWithoutSaving() => _perform(() async {
        if (connectedDevice != null && _pendingResult == null) {
          await _tracker.stopCounting();
        }
        _clearSession();
      });

  /// Stop/ACK first, then persist the final total. A storage retry cannot keep
  /// counting or create a different result for the same button press.
  Future<bool> finishExercise() async {
    if (!canFinish) return false;
    return _perform(() async {
      final workout = _activeWorkout!;
      final exercise = _activeExercise!;
      if (_pendingResult == null) {
        await _tracker.stopCounting();
        final finalStatus = trackerStatus;
        if (finalStatus == null ||
            finalStatus.exerciseId != exerciseIdForKind(exercise.kind) ||
            finalStatus.state != TrackerState.ready ||
            finalStatus.repetitions < _reps) {
          throw StateError(
              'Unable to verify the final repetition count. Refresh or reconnect your tracker.');
        }
        _reps = finalStatus.repetitions;
        _running = false;
        _paused = true;
        _pendingResult = ExerciseResult(
          workoutId: workout.id,
          exerciseId: exercise.id,
          repetitions: _reps,
          deviceId: _sessionDevice!.id,
          completedAt: DateTime.now(),
        );
      }
      final result = _pendingResult!;
      await _repository.saveResult(result);
      _results[result.key] = result;
      _clearSession(keepReps: true);
      return true;
    });
  }

  /// Android/iOS backgrounding pauses counting after any in-flight command ends.
  /// Returning to the app requires an explicit Resume; calibration is canceled.
  Future<void> pauseForBackground() async {
    await _operationDone?.future;
    if (_disposed || connectedDevice == null) return;
    if (isCalibrating) {
      await cancelCalibration();
    } else if (_running && !_paused && _pendingResult == null) {
      await togglePause();
    }
  }

  /// The root invokes this on sign-out, including if a workout route is open.
  Future<void> endSession() => _perform(() async {
        try {
          if (connectedDevice != null) await _tracker.stopCounting();
        } finally {
          await _tracker.disconnect();
          _clearSession();
        }
      });

  void _onRepetitions(int count) {
    if (_disposed ||
        !hasActiveSession ||
        _recovering ||
        _disconnected ||
        _sessionInvalid ||
        _pendingResult != null) {
      return;
    }
    _reps = math.max(_reps, count);
    _notify();
  }

  /// Status notifications include calibration progress, errors, and pause state.
  void _onStatus(TrackerStatus? status) {
    if (_disposed || _recovering) return;
    if (_learningExerciseId != null &&
        status != null &&
        status.exerciseId == _learningExerciseId &&
        status.state == TrackerState.ready &&
        status.profileAvailable &&
        status.result == 0) {
      _completedCalibrationId = _learningExerciseId;
      _learningExerciseId = null;
    }
    _deviceError = status != null && status.result != 0
        ? FitnessProtocol.resultMessage(status.result)
        : null;
    if (status == null) {
      _learningExerciseId = null;
      _completedCalibrationId = null;
      _disconnected = hasActiveSession;
      if (hasActiveSession && _pendingResult == null) {
        _paused = true;
        _trackerError =
            'Tracker disconnected. Reconnect to continue, or stop without completing.';
      }
    } else if (hasActiveSession && !_disconnected && _pendingResult == null) {
      if (status.exerciseId != exerciseIdForKind(_activeExercise!.kind)) {
        _sessionInvalid = true;
        _trackerError =
            'The tracker changed exercises. Stop this exercise and start again.';
      } else {
        _reps = math.max(_reps, status.repetitions);
        _paused = status.state != TrackerState.running;
        if (status.state == TrackerState.running ||
            status.state == TrackerState.paused) {
          _running = true;
        }
        if (status.state == TrackerState.error || !status.sensorReady) {
          _deviceError =
              'Tracker sensor is not ready. Check its connection and position, then refresh or restart.';
        }
      }
    }
    _notify();
  }

  void _onTrackerError(Object error) {
    _trackerError = error.toString();
    _notify();
  }

  void _clearSession({bool keepReps = false}) {
    _activeWorkout = null;
    _activeExercise = null;
    _sessionDevice = null;
    _pendingResult = null;
    _running = false;
    _paused = false;
    _disconnected = false;
    _sessionInvalid = false;
    if (!keepReps) _reps = 0;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_repSubscription.cancel());
    unawaited(_statusSubscription.cancel());
    unawaited(_tracker.dispose().catchError((Object _) {}));
    super.dispose();
  }
}

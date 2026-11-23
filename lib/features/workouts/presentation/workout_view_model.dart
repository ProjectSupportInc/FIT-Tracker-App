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
import '../domain/workout_journal.dart';
import '../../../core/utils/date_labels.dart';
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
  ActiveExercise? _activeRecord;
  WorkoutRepeat? _repeat;
  List<ExerciseResult> _history = [];
  Future<void> _journalWrites = Future.value();
  Timer? _reconnectTimer;
  int _reconnectAttempts = 0;
  bool _foreground = true;
  bool _restored = false;
  String? _storageError;
  bool lastFinishWasRepeat = false;
  ExercisePlan? lastFinishNextExercise;

  String? get activeAttemptId => _activeRecord?.attemptId;
  WorkoutPlan? get activeWorkout => _activeWorkout;
  ExercisePlan? get activeExercise => _activeExercise;
  bool get sessionInvalid => _sessionInvalid;
  WorkoutRepeat? get repeat => _repeat;
  List<ExerciseResult> historyFor(WorkoutPlan w, [ExercisePlan? e]) => _history
      .where((r) => r.workoutId == w.id && (e == null || r.exerciseId == e.id))
      .toList()
    ..sort((a, b) => b.completedAt.compareTo(a.completedAt));
  bool isToday(WorkoutPlan w) => isSameDate(w.scheduledAt, DateTime.now());
  bool canRepeat(WorkoutPlan w) => isToday(w) && !hasActiveSession && !_busy;
  String _newId() =>
      '${DateTime.now().microsecondsSinceEpoch}-${math.Random.secure().nextInt(0xffffffff)}';

  Future<void> _persistJournal() =>
      _writeJournal(WorkoutJournal(active: _activeRecord, repeat: _repeat));

  Future<void> _writeJournal(WorkoutJournal journal) {
    final write = _journalWrites.then((_) => _repository.writeJournal(journal));
    _journalWrites = write.then<void>((_) {
      _storageError = null;
    }, onError: (Object error, StackTrace _) {
      _storageError = 'Unable to save recovery progress: $error';
      _notify();
    });
    return write;
  }

  void _checkpoint({TrackerState? state}) {
    final record = _activeRecord;
    if (record == null) return;
    final nextState = state ?? record.state;
    if (record.repetitions == _reps &&
        record.state == nextState &&
        record.finalResult == _pendingResult) {
      return;
    }
    _activeRecord = record.copyWith(
        repetitions: _reps, state: nextState, finalResult: _pendingResult);
    unawaited(_persistJournal().catchError((Object _) {}));
  }

  bool _sameSession(TrackerStatus? status) =>
      status != null &&
      _activeRecord != null &&
      status.bootId == _activeRecord!.bootId &&
      status.sessionId == _activeRecord!.sessionId;

  Future<void> beginRepeat(WorkoutPlan workout, {ExercisePlan? exercise}) =>
      _perform(() async {
        if (!isToday(workout) ||
            hasActiveSession ||
            (exercise != null && !exerciseComplete(workout, exercise))) {
          throw StateError('Only today’s completed exercises can be repeated.');
        }
        final repeat = WorkoutRepeat(
            id: _newId(),
            workoutId: workout.id,
            exerciseIds: exercise == null
                ? workout.exercises.map((e) => e.id).toList()
                : [exercise.id]);
        await _writeJournal(WorkoutJournal(repeat: repeat));
        _repeat = repeat;
      });

  Future<void> cancelRepeat() => _perform(() async {
        if (hasActiveSession) {
          throw StateError('End the current exercise first.');
        }
        await _writeJournal(const WorkoutJournal());
        _repeat = null;
      });

  void _scheduleReconnect() {
    if (_disposed ||
        !_foreground ||
        !hasActiveSession ||
        !_disconnected ||
        _sessionInvalid ||
        _pendingResult != null ||
        _restored ||
        _reconnectTimer != null ||
        _reconnectAttempts >= 4) {
      return;
    }
    final delay = Duration(seconds: 1 << _reconnectAttempts);
    _reconnectTimer = Timer(delay, () async {
      _reconnectTimer = null;
      if (_busy) {
        _scheduleReconnect();
        return;
      }
      _reconnectAttempts++;
      try {
        await reconnectActiveExercise(automatic: true);
      } catch (_) {
        _scheduleReconnect();
      }
    });
  }

  /// Remember the exact peripheral, so reconnect never silently picks a new one.
  TrackerDevice? _sessionDevice;

  /// A device-confirmed final result survives storage failures for an exact retry.
  ExerciseResult? _pendingResult;

  // The firmware no longer carries exercise IDs or saved profiles.
  String? _preparedExerciseId;
  bool _starting = false;
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
  String? get trackerError => _storageError ?? _trackerError ?? _deviceError;
  String? get loadError => _loadError;
  bool get isLoaded => _loaded;
  int get liveReps => _reps;
  bool get isRunning => _running;
  bool get isPaused => _paused;
  bool get isTrackerBusy => _busy || (trackerStatus?.commandPending ?? false);
  bool get isDisconnected => _disconnected;
  bool get hasActiveSession => _activeExercise != null;
  bool get hasPendingResult => _pendingResult != null;
  bool get isPreparing => trackerStatus?.state.isPreparing ?? false;
  bool get canTogglePause =>
      !isTrackerBusy &&
      hasActiveSession &&
      !_disconnected &&
      !_sessionInvalid &&
      _pendingResult == null &&
      (trackerStatus!.state.isActive ||
          trackerStatus!.state == TrackerState.paused);

  /// A frozen result can be saved again without another BLE command.
  bool get canFinish =>
      !_busy &&
      (_pendingResult != null ||
          (hasActiveSession &&
              !_disconnected &&
              !_sessionInvalid &&
              connectedDevice != null &&
              (trackerStatus?.state == TrackerState.running ||
                  trackerStatus?.state == TrackerState.paused ||
                  trackerStatus?.state == TrackerState.finished) &&
              policy.targetReached(_activeExercise!, _reps)));

  bool canStartExercise(ExercisePlan exercise) =>
      !_busy &&
      !hasActiveSession &&
      !(trackerStatus?.commandPending ?? true) &&
      connectedDevice != null &&
      trackerStatus != null &&
      _preparedExerciseId == exercise.id;

  /// Root startup calls this. Failures remain visible and can be retried.
  Future<void> load() async {
    _loadError = null;
    try {
      _plans = await _repository.fetchWorkouts();
      _results = Map.of(await _repository.fetchResults());
      _history = List.of(await _repository.fetchHistory());
      final journal = await _repository.readJournal();
      _repeat = journal.repeat;
      _activeRecord = journal.active;
      if (_activeRecord != null) {
        final record = _activeRecord!;
        _activeWorkout = _plans.firstWhere((w) => w.id == record.workoutId);
        _activeExercise = _activeWorkout!.exercises
            .firstWhere((e) => e.id == record.exerciseId);
        _sessionDevice =
            TrackerDevice(id: record.deviceId, name: record.deviceName);
        _reps = record.repetitions;
        _pendingResult = record.finalResult;
        _disconnected = _pendingResult == null;
        _restored = true;
        _paused = true;
      }
      if (_repeat != null &&
          !_plans.any((w) => w.id == _repeat!.workoutId && isToday(w))) {
        _repeat = null;
        await _persistJournal();
      }
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

  /// Selection stays on the phone. Setup reads the device without changing it.
  Future<void> prepareExercise(ExercisePlan exercise) => _perform(() async {
        if (hasActiveSession) {
          throw StateError('An exercise is already active.');
        }
        if (connectedDevice == null) {
          throw StateError('Connect your tracker first.');
        }
        _preparedExerciseId = null;
        await _tracker.refreshStatus();
        _preparedExerciseId = exercise.id;
      });

  Future<void> refreshTrackerStatus() =>
      _perform(() => _tracker.refreshStatus());

  Future<void> startExercise(WorkoutPlan workout, ExercisePlan exercise) async {
    if (!canStartExercise(exercise)) {
      throw StateError('Connect your tracker before starting.');
    }
    await _perform(() async {
      final repeating = _repeat?.workoutId == workout.id &&
          _repeat?.exerciseId == exercise.id &&
          isToday(workout);
      if (!repeating &&
          (status(workout) != WorkoutAvailability.ready ||
              !exerciseUnlocked(workout, exercise) ||
              exerciseComplete(workout, exercise))) {
        throw StateError('This exercise is not available yet.');
      }
      // Setup warns before replacing a session that has no phone-side recovery record.
      if (trackerStatus?.state != TrackerState.idle &&
          trackerStatus?.state != TrackerState.finished) {
        await _tracker.reset();
      }
      _starting = true;
      _activeWorkout = workout;
      _activeExercise = exercise;
      _sessionDevice = connectedDevice;
      _reps = 0;
      _pendingResult = null;
      _sessionInvalid = false;
      _disconnected = false;
      _restored = false;
      _reconnectAttempts = 0;
      _activeRecord = ActiveExercise(
          workoutId: workout.id,
          exerciseId: exercise.id,
          attemptId: _newId(),
          deviceId: _sessionDevice!.id,
          deviceName: _sessionDevice!.name,
          bootId: trackerStatus!.bootId,
          sessionId: 1 + math.Random.secure().nextInt(0xffffffff),
          runId: repeating ? _repeat!.id : null);
      bool sent = false;
      try {
        await _persistJournal();
        sent = true;
        await _tracker.startCounting(sessionId: _activeRecord!.sessionId);
        _running = true;
        _onStatus(trackerStatus);
      } catch (_) {
        if (!sent) {
          _clearSession();
        } else {
          // An uncertain START stays recoverable; never reset it blindly.
          _disconnected = true;
          _scheduleReconnect();
        }
        rethrow;
      } finally {
        _starting = false;
      }
    });
  }

  Future<void> togglePause() => _perform(() async {
        if (!hasActiveSession ||
            _disconnected ||
            _sessionInvalid ||
            _pendingResult != null ||
            !(trackerStatus!.state.isActive ||
                trackerStatus!.state == TrackerState.paused)) {
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

  /// Identity is checked before any command can alter the recovered session.
  Future<void> reconnectActiveExercise({bool automatic = false}) =>
      _perform(() async {
        final device = _sessionDevice;
        final record = _activeRecord;
        if (device == null || record == null || _pendingResult != null) {
          throw StateError('There is no active tracker session to reconnect.');
        }
        _reconnectTimer?.cancel();
        _reconnectTimer = null;
        _recovering = true;
        try {
          await _tracker.connect(device);
          _tracker.bindSession(
              bootId: record.bootId, sessionId: record.sessionId);
          await _tracker.refreshStatus();
          for (var i = 0;
              trackerStatus?.commandPending == true && i < 20;
              i++) {
            await Future<void>.delayed(const Duration(milliseconds: 100));
            await _tracker.refreshStatus();
          }
          final restored = trackerStatus;
          if (!_sameSession(restored) ||
              restored!.repetitions < _reps ||
              restored.state == TrackerState.idle ||
              restored.state == TrackerState.error) {
            _sessionInvalid = true;
            throw StateError(
                'This tracker session was interrupted or replaced. Keep the recorded reps and start a new attempt.');
          }
          if (restored.commandPending) {
            throw StateError(
                'The tracker is still completing an operation. Try reconnecting again.');
          }
          if (restored.state.isActive && (!automatic || _restored)) {
            await _tracker.pauseCounting();
          }
          _reps = trackerStatus!.repetitions;
          _disconnected = false;
          _sessionInvalid = false;
          _restored = false;
          _reconnectAttempts = 0;
          _trackerError = null;
          _running = trackerStatus!.state.isActive ||
              trackerStatus!.state == TrackerState.paused;
          _paused = trackerStatus!.state == TrackerState.paused;
          _checkpoint(state: trackerStatus!.state);
        } finally {
          _recovering = false;
        }
      });

  /// Records only the last confirmed count; it does not claim a completed set.
  Future<void> keepInterruptedResult() => _perform(() async {
        final record = _activeRecord;
        if (record == null) return;
        final result = ExerciseResult(
            workoutId: record.workoutId,
            exerciseId: record.exerciseId,
            repetitions: _reps,
            deviceId: record.deviceId,
            completedAt: DateTime.now(),
            attemptId: record.attemptId,
            runId: record.runId,
            completed: false);
        await _journalWrites;
        await _repository.commitResult(result, const WorkoutJournal());
        _history.add(result);
        _repeat = null;
        _clearSession();
        await _tracker.disconnect().catchError((Object _) {});
      });

  /// Offline stop only discards the phone session. The sensor may continue;
  /// a later new exercise resets that abandoned session before START.
  Future<void> stopWithoutSaving() => _perform(() async {
        if (connectedDevice != null &&
            _pendingResult == null &&
            !_sessionInvalid &&
            _sameSession(trackerStatus)) {
          if (trackerStatus?.state == TrackerState.error) {
            await _tracker.reset();
          } else {
            await _tracker.stopCounting();
          }
        }
        final repeat = _activeRecord?.runId != null ? null : _repeat;
        await _writeJournal(WorkoutJournal(repeat: repeat));
        _repeat = repeat;
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
        if (!_sameSession(finalStatus) ||
            finalStatus == null ||
            finalStatus.state != TrackerState.finished ||
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
          attemptId: _activeRecord!.attemptId,
          runId: _activeRecord!.runId,
        );
      }
      final result = _pendingResult!;
      _checkpoint(state: TrackerState.finished);
      await _journalWrites;
      lastFinishWasRepeat = _activeRecord!.runId != null;
      final nextRepeat = lastFinishWasRepeat ? _repeat?.advance() : _repeat;
      final index = workout.exercises.indexWhere((e) => e.id == exercise.id);
      lastFinishNextExercise = lastFinishWasRepeat
          ? (nextRepeat == null
              ? null
              : workout.exercises
                  .firstWhere((e) => e.id == nextRepeat.exerciseId))
          : (index + 1 < workout.exercises.length
              ? workout.exercises[index + 1]
              : null);
      await _repository.commitResult(
          result, WorkoutJournal(repeat: nextRepeat));
      _repeat = nextRepeat;
      _results[result.key] = result;
      _history.removeWhere((r) => r.recordId == result.recordId);
      _history.add(result);
      _clearSession(keepReps: true);
      return true;
    });
  }

  /// Android/iOS backgrounding pauses counting after any in-flight command ends.
  /// Returning requires an explicit RESUME. Firmware restarts preparation if
  /// paused before template lock; a learned template survives a pause.
  Future<void> pauseForBackground() async {
    _foreground = false;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _operationDone?.future;
    if (_disposed || connectedDevice == null) return;
    if (hasActiveSession &&
        trackerStatus!.state.isActive &&
        _pendingResult == null) {
      await togglePause();
    }
  }

  void returnToForeground() {
    _foreground = true;
    _scheduleReconnect();
  }

  /// An unresolved attempt must be kept or ended before changing accounts.
  Future<void> endSession() => _perform(() async {
        if (hasActiveSession) {
          throw StateError(
              'End or keep your current exercise before signing out.');
        }
        await _tracker.disconnect();
        _preparedExerciseId = null;
      });

  void _onRepetitions(int count) {
    if (_disposed ||
        !hasActiveSession ||
        _recovering ||
        _disconnected ||
        _sessionInvalid ||
        _pendingResult != null ||
        !_sameSession(trackerStatus)) {
      return;
    }
    _reps = math.max(_reps, count);
    _checkpoint();
    _notify();
  }

  /// Status drives preparation, pause, error and final-count UI.
  void _onStatus(TrackerStatus? status) {
    if (_disposed || _recovering) return;
    _deviceError = status?.event == TrackerEvent.commandRejected
        ? FitnessProtocol.resultMessage(status!.detail)
        : null;
    if (status == null) {
      _preparedExerciseId = null;
      _disconnected = hasActiveSession;
      if (hasActiveSession && _pendingResult == null) {
        _trackerError = 'Connection lost. Reconnecting to your tracker…';
        _scheduleReconnect();
      }
    } else if (hasActiveSession && !_disconnected && _pendingResult == null) {
      if (_starting && !_sameSession(status)) return;
      if (!_sameSession(status) ||
          (!_starting &&
              (status.state == TrackerState.idle ||
                  status.repetitions < _reps))) {
        _sessionInvalid = true;
        _trackerError =
            'The tracker restarted or the session changed. Keep your recorded reps and start a new attempt.';
        _running = false;
        _notify();
        return;
      }
      _reps = math.max(_reps, status.repetitions);
      _paused = status.state == TrackerState.paused;
      _running = status.state.isActive || _paused;
      _checkpoint(state: status.state);
      if (status.state == TrackerState.error) {
        _deviceError =
            'The tracker reported an error. Stop this session and check '
            'the sensor before starting again.';
      }
    }
    _notify();
  }

  void _onTrackerError(Object error) {
    _trackerError = error.toString();
    _notify();
  }

  void _clearSession({bool keepReps = false}) {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _activeRecord = null;
    _restored = false;
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
    _reconnectTimer?.cancel();
    unawaited(_repSubscription.cancel());
    unawaited(_statusSubscription.cancel());
    unawaited(_tracker.dispose().catchError((Object _) {}));
    super.dispose();
  }
}

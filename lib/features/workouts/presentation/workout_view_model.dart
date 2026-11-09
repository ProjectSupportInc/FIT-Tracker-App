import 'dart:async';
import 'package:flutter/foundation.dart';

import '../../tracker/data/tracker_gateway.dart';
import '../../tracker/domain/tracker_device.dart';
import '../data/workout_repository.dart';
import '../domain/workout_models.dart';
import '../domain/workout_policy.dart';

class WorkoutViewModel extends ChangeNotifier {
  WorkoutViewModel({required WorkoutRepository repository, required TrackerGateway tracker})
      : _repository = repository, _tracker = tracker;

  final WorkoutRepository _repository;
  final TrackerGateway _tracker;
  final WorkoutPolicy policy = const WorkoutPolicy();
  List<WorkoutPlan> _plans = [];
  Map<String, ExerciseResult> _results = {};
  final Set<String> _calibrationProfiles = {};
  StreamSubscription<int>? _repSubscription;
  WorkoutPlan? _activeWorkout;
  ExercisePlan? _activeExercise;
  int _reps = 0;
  bool _running = false;
  bool _paused = false;
  bool _loaded = false;

  List<WorkoutPlan> get workouts => List.unmodifiable(_plans);
  Map<String, ExerciseResult> get results => Map.unmodifiable(_results);
  TrackerDevice? get connectedDevice => _tracker.connectedDevice;
  bool get isLoaded => _loaded;
  int get liveReps => _reps;
  bool get isRunning => _running;
  bool get isPaused => _paused;

  Future<void> load() async {
    _plans = await _repository.fetchWorkouts();
    _results = await _repository.fetchResults();
    _loaded = true;
    notifyListeners();
  }

  WorkoutAvailability status(WorkoutPlan workout) =>
      policy.availability(workout, _plans, _results, DateTime.now());

  bool workoutComplete(WorkoutPlan workout) => policy.workoutCompleted(workout, _results);
  bool exerciseComplete(WorkoutPlan w, ExercisePlan e) => policy.exerciseCompleted(w, e, _results);
  bool exerciseUnlocked(WorkoutPlan w, ExercisePlan e) =>
      policy.exerciseUnlocked(w, e, _results);

  int doneCount(WorkoutPlan workout) =>
      workout.exercises.where((ex) => exerciseComplete(workout, ex)).length;

  ExerciseResult? resultFor(WorkoutPlan w, ExercisePlan e) => _results[exerciseKey(w, e)];

  Future<List<TrackerDevice>> scan() => _tracker.scan();

  Future<void> connect(TrackerDevice device) async {
    await _tracker.connect(device);
    notifyListeners();
  }

  String _calibrationKey(ExercisePlan exercise) => '${connectedDevice?.id}::${exercise.kind}';
  bool isCalibrated(ExercisePlan exercise) =>
      connectedDevice != null && _calibrationProfiles.contains(_calibrationKey(exercise));

  Future<void> saveCalibration(ExercisePlan exercise) async {
    if (connectedDevice == null) throw StateError('Connect device before calibrating');
    await _tracker.saveCalibration(exerciseKind: exercise.kind, referenceReps: 3);
    _calibrationProfiles.add(_calibrationKey(exercise));
    notifyListeners();
  }

  Future<void> startExercise(WorkoutPlan workout, ExercisePlan exercise) async {
    if (status(workout) != WorkoutAvailability.ready ||
        !exerciseUnlocked(workout, exercise) || exerciseComplete(workout, exercise)) {
      throw StateError('Exercise is not available');
    }
    if (connectedDevice == null) throw StateError('Connect a wearable first');
    await _repSubscription?.cancel();
    _activeWorkout = workout;
    _activeExercise = exercise;
    _reps = 0;
    _repSubscription = _tracker.repetitionCounts.listen((count) {
      _reps = count;
      notifyListeners();
    });
    try {
      await _tracker.startCounting(exerciseKind: exercise.kind);
      _running = true;
      _paused = false;
      notifyListeners();
    } catch (_) {
      await _repSubscription?.cancel();
      _activeWorkout = null;
      _activeExercise = null;
      rethrow;
    }
  }

  Future<void> togglePause() async {
    if (!_running) return;
    if (_paused) {
      await _tracker.resumeCounting();
    } else {
      await _tracker.pauseCounting();
    }
    _paused = !_paused;
    notifyListeners();
  }

  Future<void> stopWithoutSaving() async {
    await _tracker.stopCounting();
    await _repSubscription?.cancel();
    _repSubscription = null;
    _running = false;
    _paused = false;
    _activeWorkout = null;
    _activeExercise = null;
    _reps = 0;
    notifyListeners();
  }

  Future<bool> finishExercise() async {
    final workout = _activeWorkout;
    final exercise = _activeExercise;
    if (workout == null || exercise == null || !policy.targetReached(exercise, _reps)) {
      return false;
    }
    final result = ExerciseResult(
      workoutId: workout.id, exerciseId: exercise.id,
      repetitions: _reps, deviceId: connectedDevice!.id,
      completedAt: DateTime.now(),
    );
    await _repository.saveResult(result);
    _results[result.key] = result;
    await _tracker.stopCounting();
    await _repSubscription?.cancel();
    _repSubscription = null;
    _running = false;
    _paused = false;
    _activeWorkout = null;
    _activeExercise = null;
    notifyListeners();
    return true;
  }

  @override
  void dispose() {
    _repSubscription?.cancel();
    _tracker.dispose();
    super.dispose();
  }
}

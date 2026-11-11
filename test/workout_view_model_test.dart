import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:repform_app/features/tracker/data/tracker_gateway.dart';
import 'package:repform_app/features/tracker/domain/tracker_device.dart';
import 'package:repform_app/features/tracker/domain/tracker_status.dart';
import 'package:repform_app/features/workouts/data/workout_repository.dart';
import 'package:repform_app/features/workouts/domain/workout_models.dart';
import 'package:repform_app/features/workouts/presentation/workout_view_model.dart';

/// Deterministic peripheral: tests choose when real-looking status/rep events arrive.
class TestTracker implements TrackerGateway {
  final controller = StreamController<int>.broadcast(sync: true);
  final statusController =
      StreamController<TrackerStatus?>.broadcast(sync: true);
  final profiles = <int>{};
  TrackerDevice? device;
  TrackerStatus? _status;
  TrackerStatus? restoredOnConnect;
  int stopCalls = 0;
  int startCalls = 0;
  bool failStop = false;

  @override
  Stream<int> get repetitionCounts => controller.stream;
  @override
  Stream<TrackerStatus?> get statuses => statusController.stream;
  @override
  TrackerStatus? get status => _status;
  @override
  TrackerDevice? get connectedDevice => device;

  void emitStatus(TrackerStatus? value) {
    if (value == null) device = null;
    _status = value;
    statusController.add(value);
  }

  void publish(TrackerState state, {int? exerciseId, int? reps, int? calReps}) {
    final id = exerciseId ?? _status?.exerciseId ?? 0;
    emitStatus(TrackerStatus(
        state: state,
        exerciseId: id,
        sensorReady: true,
        profileAvailable: profiles.contains(id),
        repetitions: reps ?? _status?.repetitions ?? 0,
        calibrationReps: calReps ?? _status?.calibrationReps ?? 0));
  }

  void emitReps(int count) {
    publish(_status?.state ?? TrackerState.running, reps: count);
    controller.add(count);
  }

  void completeCalibration() {
    profiles.add(_status!.exerciseId);
    publish(TrackerState.ready, calReps: 3);
  }

  @override
  Future<List<TrackerDevice>> scan() async =>
      const [TrackerDevice(id: 'FT-01', name: 'Test tracker')];
  @override
  Future<void> connect(TrackerDevice next) async {
    device = next;
    _status = restoredOnConnect ?? _status;
    _status ??= const TrackerStatus(
        state: TrackerState.idle,
        exerciseId: 0,
        sensorReady: true,
        profileAvailable: false,
        repetitions: 0,
        calibrationReps: 0);
    statusController.add(_status);
  }

  @override
  Future<void> disconnect() async {
    emitStatus(null);
  }

  @override
  Future<void> selectExercise({required String exerciseKind}) async {
    final id = exerciseIdForKind(exerciseKind);
    publish(profiles.contains(id) ? TrackerState.ready : TrackerState.selected,
        exerciseId: id, reps: 0, calReps: profiles.contains(id) ? 3 : 0);
  }

  @override
  Future<void> beginCalibration({required String exerciseKind}) async {
    profiles.remove(exerciseIdForKind(exerciseKind));
    publish(TrackerState.calibrating, calReps: 0);
  }

  @override
  Future<void> refreshStatus() async {
    statusController.add(_status);
  }

  @override
  Future<void> startCounting({required String exerciseKind}) async {
    startCalls++;
    publish(TrackerState.running, reps: 0);
  }

  @override
  Future<void> pauseCounting() async {
    publish(TrackerState.paused);
  }

  @override
  Future<void> resumeCounting() async {
    startCalls++;
    publish(TrackerState.running);
  }

  @override
  Future<void> stopCounting() async {
    stopCalls++;
    if (failStop) throw StateError('Device unavailable');
    publish(profiles.contains(_status?.exerciseId)
        ? TrackerState.ready
        : TrackerState.selected);
  }

  @override
  Future<void> dispose() async {
    await controller.close();
    await statusController.close();
  }
}

class TestRepository implements WorkoutRepository {
  TestRepository(this.plan);
  final WorkoutPlan plan;
  final results = <String, ExerciseResult>{};

  @override
  Future<List<WorkoutPlan>> fetchWorkouts() async => [plan];
  @override
  Future<Map<String, ExerciseResult>> fetchResults() async => Map.of(results);
  @override
  Future<void> saveResult(ExerciseResult result) async {
    results[result.key] = result;
  }
}

void main() {
  final day = DateTime.now();
  const curl = ExercisePlan(
      id: 'curl',
      name: 'Dumbbell Curl',
      kind: 'curl',
      targetReps: 5,
      coachTip: 'Control movement');
  const pushup = ExercisePlan(
      id: 'push',
      name: 'Push-up',
      kind: 'push-up',
      targetReps: 4,
      coachTip: 'Straight back');
  final plan = WorkoutPlan(
      id: 'today',
      title: 'Today',
      description: '',
      scheduledAt: DateTime(day.year, day.month, day.day, 18),
      exercises: const [curl, pushup]);

  test(
      'Device is reusable, calibrations are exercise-specific, rep overflow is saved',
      () async {
    final tracker = TestTracker();
    final repo = TestRepository(plan);
    final vm = WorkoutViewModel(repository: repo, tracker: tracker);
    await vm.load();
    await vm.connect(const TrackerDevice(id: 'FT-01', batteryPercent: 100));
    await vm.prepareExercise(curl);
    await vm.beginCalibration(curl);
    tracker.completeCalibration();
    expect(vm.isCalibrated(curl), true);
    expect(vm.isCalibrated(pushup), false);

    await vm.startExercise(plan, curl);
    tracker.emitReps(8);
    await Future<void>.delayed(Duration.zero);
    expect(vm.liveReps, 8);
    expect(await vm.finishExercise(), true);
    expect(vm.resultFor(plan, curl)?.repetitions, 8);

    expect(vm.connectedDevice?.id, 'FT-01');
    expect(vm.exerciseUnlocked(plan, pushup), true);
    vm.dispose();
  });

  test('Stopping early cannot unlock the next exercise', () async {
    final tracker = TestTracker();
    final repo = TestRepository(plan);
    final vm = WorkoutViewModel(repository: repo, tracker: tracker);
    await vm.load();
    await vm.connect(const TrackerDevice(id: 'FT-01', batteryPercent: 100));
    await vm.prepareExercise(curl);
    await vm.beginCalibration(curl);
    tracker.completeCalibration();
    await vm.startExercise(plan, curl);
    tracker.emitReps(3);
    await Future<void>.delayed(Duration.zero);
    expect(await vm.finishExercise(), false);
    await vm.stopWithoutSaving();
    expect(vm.exerciseComplete(plan, curl), false);
    expect(vm.exerciseUnlocked(plan, pushup), false);
    vm.dispose();
  });

  Future<({WorkoutViewModel vm, TestTracker tracker, TestRepository repo})>
      active() async {
    final tracker = TestTracker();
    final repo = TestRepository(plan);
    final vm = WorkoutViewModel(repository: repo, tracker: tracker);
    addTearDown(vm.dispose);
    await vm.load();
    await vm.connect((await tracker.scan()).first);
    await vm.prepareExercise(curl);
    await vm.beginCalibration(curl);
    tracker.completeCalibration();
    await vm.startExercise(plan, curl);
    return (vm: vm, tracker: tracker, repo: repo);
  }

  test('Starting requires the selected device to confirm real calibration',
      () async {
    final tracker = TestTracker();
    final vm =
        WorkoutViewModel(repository: TestRepository(plan), tracker: tracker);
    addTearDown(vm.dispose);
    await vm.load();
    await vm.connect((await tracker.scan()).first);
    await vm.prepareExercise(curl);
    expect(vm.canStartExercise(curl), isFalse);
    await expectLater(vm.startExercise(plan, curl), throwsStateError);
    await vm.beginCalibration(curl);
    expect(vm.isCalibrated(curl), isFalse);
    tracker.completeCalibration();
    expect(vm.canStartExercise(curl), isTrue);
    expect(vm.canStartExercise(pushup), isFalse);
  });

  test('Disconnect preserves reps and reconnect pauses until explicit resume',
      () async {
    final s = await active();
    s.tracker.emitReps(6);
    s.tracker.restoredOnConnect = const TrackerStatus(
        state: TrackerState.paused,
        exerciseId: 1,
        sensorReady: true,
        profileAvailable: true,
        repetitions: 7,
        calibrationReps: 3);
    s.tracker.emitStatus(null);
    expect(s.vm.isDisconnected, isTrue);
    expect(s.vm.liveReps, 6);
    expect(s.vm.canFinish, isFalse);
    await s.vm.reconnectActiveExercise();
    expect(s.vm.liveReps, 7);
    expect(s.vm.isDisconnected, isFalse);
    expect(s.vm.isPaused, isTrue);
    expect(s.tracker.startCalls, 1);
    await s.vm.togglePause();
    expect(s.tracker.startCalls, 2);
    expect(s.vm.isPaused, isFalse);
  });

  test('A reset tracker cannot be resumed or falsely completed after reconnect',
      () async {
    final s = await active();
    s.tracker.emitReps(8);
    s.tracker.emitStatus(null);
    await expectLater(s.vm.reconnectActiveExercise(), throwsStateError);
    expect(s.vm.canFinish, isFalse);
    expect(s.repo.results, isEmpty);
    expect(s.tracker.startCalls, 1);
    await s.vm.stopWithoutSaving();
    expect(s.vm.hasActiveSession, isFalse);
  });

  test('Failure to confirm stopping never writes a completion', () async {
    final s = await active();
    s.tracker.emitReps(8);
    s.tracker.failStop = true;
    await expectLater(s.vm.finishExercise(), throwsStateError);
    expect(s.repo.results, isEmpty);
    expect(s.vm.hasPendingResult, isFalse);
    expect(s.vm.hasActiveSession, isTrue);
    s.tracker.failStop = false;
    expect(await s.vm.finishExercise(), isTrue);
    expect(s.repo.results.values.single.repetitions, 8);
  });

  test(
      'Offline stop discards the local session without saving or sending commands',
      () async {
    final s = await active();
    s.tracker.emitReps(8);
    s.tracker.emitStatus(null);
    await s.vm.stopWithoutSaving();
    expect(s.tracker.stopCalls, 0);
    expect(s.repo.results, isEmpty);
    expect(s.vm.hasActiveSession, isFalse);
  });

  test(
      'Backgrounding pauses an active exercise without saving or auto-resuming',
      () async {
    final s = await active();
    s.tracker.emitReps(4);
    await s.vm.pauseForBackground();
    expect(s.vm.isPaused, isTrue);
    expect(s.vm.liveReps, 4);
    expect(s.repo.results, isEmpty);
    expect(s.tracker.startCalls, 1);
  });

  test('Canceling recalibration does not report an old restored profile as new',
      () async {
    final tracker = TestTracker();
    final vm =
        WorkoutViewModel(repository: TestRepository(plan), tracker: tracker);
    addTearDown(vm.dispose);
    await vm.load();
    await vm.connect((await tracker.scan()).first);
    await vm.prepareExercise(curl);
    await vm.beginCalibration(curl);
    tracker.completeCalibration();
    expect(vm.didCompleteCalibration(curl), isTrue);
    await vm.beginCalibration(curl);
    // A real peripheral restores its previous durable profile when canceled.
    tracker.profiles.add(1);
    await vm.cancelCalibration();
    expect(vm.isCalibrated(curl), isTrue);
    expect(vm.didCompleteCalibration(curl), isFalse);
  });
}

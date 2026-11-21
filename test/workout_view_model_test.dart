import 'package:flutter_test/flutter_test.dart';

import 'package:repform_app/features/tracker/data/mock_tracker_gateway.dart';
import 'package:repform_app/features/tracker/domain/tracker_device.dart';
import 'package:repform_app/features/tracker/domain/tracker_status.dart';
import 'package:repform_app/features/workouts/data/workout_repository.dart';
import 'package:repform_app/features/workouts/domain/workout_models.dart';
import 'package:repform_app/features/workouts/presentation/workout_view_model.dart';

/// Deterministic peripheral with controllable command failures and reconnects.
class TestTracker extends MockTrackerGateway {
  TrackerStatus? restoredOnConnect;
  int stopCalls = 0;
  int startCalls = 0;
  int resumeCalls = 0;
  int resetCalls = 0;
  bool failStop = false;

  @override
  Future<void> connect(TrackerDevice next) async {
    await super.connect(next);
    if (restoredOnConnect != null) emitStatus(restoredOnConnect);
  }

  @override
  Future<void> startCounting() async {
    startCalls++;
    await super.startCounting();
  }

  @override
  Future<void> resumeCounting() async {
    resumeCalls++;
    await super.resumeCounting();
  }

  @override
  Future<void> reset() async {
    resetCalls++;
    await super.reset();
  }

  @override
  Future<void> stopCounting() async {
    stopCalls++;
    if (failStop) throw StateError('Device unavailable');
    await super.stopCounting();
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

  test('Start learns a new movement; calibration reps and overflow are saved',
      () async {
    final tracker = TestTracker();
    final repo = TestRepository(plan);
    final vm = WorkoutViewModel(repository: repo, tracker: tracker);
    await vm.load();
    await vm.connect(const TrackerDevice(id: 'FT-01', batteryPercent: 100));
    await vm.prepareExercise(curl);
    await vm.startExercise(plan, curl);
    expect(vm.isPreparing, isTrue);
    expect(vm.liveReps, 0);
    tracker.completeCalibration();
    expect(vm.liveReps, 3);
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
    await vm.startExercise(plan, curl);
    tracker.completeCalibration();
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
    await vm.startExercise(plan, curl);
    tracker.completeCalibration();
    return (vm: vm, tracker: tracker, repo: repo);
  }

  test('Selection stays local; START begins preparation, not counting',
      () async {
    final tracker = TestTracker();
    final vm =
        WorkoutViewModel(repository: TestRepository(plan), tracker: tracker);
    addTearDown(vm.dispose);
    await vm.load();
    expect(vm.canStartExercise(curl), isFalse);
    await vm.connect((await tracker.scan()).first);
    await vm.prepareExercise(curl);
    expect(vm.canStartExercise(curl), isTrue);
    expect(vm.canStartExercise(pushup), isFalse);
    await vm.startExercise(plan, curl);
    expect(vm.isPreparing, isTrue);
    expect(vm.canFinish, isFalse);
    expect(tracker.startCalls, 1);
    expect(tracker.resetCalls, 0);
  });

  test('Disconnect preserves reps and reconnect pauses until explicit resume',
      () async {
    final s = await active();
    s.tracker.emitReps(6);
    s.tracker.restoredOnConnect = const TrackerStatus(
        state: TrackerState.running, repetitions: 7, calibrationReps: 3);
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
    expect(s.tracker.startCalls, 1);
    expect(s.tracker.resumeCalls, 1);
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

  test('Backgrounding preparation pauses; resume restarts pickup', () async {
    final s = await active();
    await s.vm.stopWithoutSaving();
    await s.vm.prepareExercise(curl);
    await s.vm.startExercise(plan, curl);
    s.tracker.publish(TrackerState.calibrating, reps: 0, calReps: 2);
    await s.vm.pauseForBackground();
    expect(s.vm.isPaused, isTrue);
    await s.vm.togglePause();
    expect(s.vm.trackerStatus!.state, TrackerState.waitPickup);
    expect(s.vm.liveReps, 0);
  });

  test('Starting deliberately resets an abandoned or faulted device session',
      () async {
    final s = await active();
    await s.vm.stopWithoutSaving();
    s.tracker.publish(TrackerState.error);
    await s.vm.prepareExercise(curl);
    await s.vm.startExercise(plan, curl);
    expect(s.tracker.resetCalls, 1);
    expect(s.vm.trackerStatus!.state, TrackerState.waitPickup);
  });

  test('Sensor error blocks completion; stop resets ERROR', () async {
    final s = await active();
    s.tracker.emitReps(8);
    s.tracker.publish(TrackerState.error);
    expect(s.vm.canFinish, isFalse);
    await s.vm.stopWithoutSaving();
    expect(s.tracker.resetCalls, 1);
    expect(s.repo.results, isEmpty);
  });

  test('A lost FINISH reply can be recovered as FINISHED without starting over',
      () async {
    final s = await active();
    s.tracker.emitReps(6);
    s.tracker.emitStatus(null);
    s.tracker.restoredOnConnect =
        const TrackerStatus(state: TrackerState.finished, repetitions: 7);
    await s.vm.reconnectActiveExercise();
    expect(s.vm.canFinish, isTrue);
    expect(await s.vm.finishExercise(), isTrue);
    expect(s.repo.results.values.single.repetitions, 7);
  });
}

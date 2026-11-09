import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import '../lib/features/tracker/data/tracker_gateway.dart';
import '../lib/features/tracker/domain/tracker_device.dart';
import '../lib/features/workouts/data/workout_repository.dart';
import '../lib/features/workouts/domain/workout_models.dart';
import '../lib/features/workouts/presentation/workout_view_model.dart';

class TestTracker implements TrackerGateway {
  final controller = StreamController<int>.broadcast();
  TrackerDevice? device;

  @override
  Stream<int> get repetitionCounts => controller.stream;
  @override
  TrackerDevice? get connectedDevice => device;
  @override
  Future<List<TrackerDevice>> scan() async => const [TrackerDevice(id: 'FT-01', batteryPercent: 100)];
  @override
  Future<void> connect(TrackerDevice next) async { device = next; }
  @override
  Future<void> disconnect() async { device = null; }
  @override
  Future<void> startCounting({required String exerciseKind}) async {}
  @override
  Future<void> saveCalibration({required String exerciseKind, required int referenceReps}) async {}
  @override
  Future<void> pauseCounting() async {}
  @override
  Future<void> resumeCounting() async {}
  @override
  Future<void> stopCounting() async {}
  @override
  Future<void> dispose() async { await controller.close(); }
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
  Future<void> saveResult(ExerciseResult result) async { results[result.key] = result; }
}

void main() {
  final day = DateTime.now();
  const curl = ExercisePlan(id: 'curl', name: 'Dumbbell Curl', kind: 'curl',
    targetReps: 5, coachTip: 'Control movement');
  const pushup = ExercisePlan(id: 'push', name: 'Push-up', kind: 'push-up',
    targetReps: 4, coachTip: 'Straight back');
  final plan = WorkoutPlan(id: 'today', title: 'Today', description: '',
    scheduledAt: DateTime(day.year, day.month, day.day, 18),
    exercises: const [curl, pushup]);

  test('Device is reusable, calibrations are exercise-specific, rep overflow is saved', () async {
    final tracker = TestTracker();
    final repo = TestRepository(plan);
    final vm = WorkoutViewModel(repository: repo, tracker: tracker);
    await vm.load();
    await vm.connect(const TrackerDevice(id: 'FT-01', batteryPercent: 100));
    await vm.saveCalibration(curl);
    expect(vm.isCalibrated(curl), true);
    expect(vm.isCalibrated(pushup), false);

    await vm.startExercise(plan, curl);
    tracker.controller.add(8);
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
    await vm.startExercise(plan, curl);
    tracker.controller.add(3);
    await Future<void>.delayed(Duration.zero);
    expect(await vm.finishExercise(), false);
    await vm.stopWithoutSaving();
    expect(vm.exerciseComplete(plan, curl), false);
    expect(vm.exerciseUnlocked(plan, pushup), false);
    vm.dispose();
  });
}

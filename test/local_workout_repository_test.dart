import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:repform_app/features/workouts/data/local_workout_repository.dart';
import 'package:repform_app/features/workouts/domain/workout_models.dart';

void main() {
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('fittracker-history-');
  });
  tearDown(() async {
    await directory.delete(recursive: true);
  });

  test('Saved completions survive recreation without fabricated demo results',
      () async {
    final day = DateTime(2026, 11, 10);
    LocalWorkoutRepository repository() => LocalWorkoutRepository(
        directory: () async => directory, now: () => day);
    final first = repository();
    final plans = await first.fetchWorkouts();
    expect(await first.fetchResults(), isEmpty);
    final plan = plans.firstWhere((p) => p.title == 'Upper Body Focus');
    final exercise = plan.exercises.first;
    final result = ExerciseResult(
        workoutId: plan.id,
        exerciseId: exercise.id,
        repetitions: 12,
        deviceId: 'actual-peripheral-id',
        completedAt: day);
    await first.saveResult(result);
    final reloaded = repository();
    expect((await reloaded.fetchWorkouts()).length, plans.length);
    final saved = (await reloaded.fetchResults())[result.key]!;
    expect(saved.repetitions, 12);
    expect(saved.deviceId, 'actual-peripheral-id');
    expect(saved.completedAt, day);
  });

  test('New calendar days have different IDs and preserve earlier history',
      () async {
    final first = LocalWorkoutRepository(
        directory: () async => directory, now: () => DateTime(2026, 11, 10));
    final oldPlans = await first.fetchWorkouts();
    final next = LocalWorkoutRepository(
        directory: () async => directory, now: () => DateTime(2026, 11, 11));
    final newPlans = await next.fetchWorkouts();
    expect(newPlans.map((p) => p.id).toSet().length, newPlans.length);
    expect(newPlans.map((p) => p.id), containsAll(oldPlans.map((p) => p.id)));
    final upper = newPlans.where((p) => p.title == 'Upper Body Focus').toList();
    expect(upper.length, 2);
    expect(upper.first.id, isNot(upper.last.id));
  });

  test('Malformed stored history is reported and never silently overwritten',
      () async {
    final file = File('${directory.path}/workouts-v1.json');
    await file.writeAsString('broken history');
    final repo = LocalWorkoutRepository(directory: () async => directory);
    await expectLater(repo.fetchWorkouts(), throwsFormatException);
    expect(await file.readAsString(), 'broken history');
  });

  test('Failed write does not publish a result in memory', () async {
    final repo = LocalWorkoutRepository(directory: () async => directory);
    final plan = (await repo.fetchWorkouts()).first;
    // A directory at the temp-file name deterministically rejects file writes.
    await Directory('${directory.path}/workouts-v1.json.tmp').create();
    await expectLater(
        repo.saveResult(ExerciseResult(
            workoutId: plan.id,
            exerciseId: plan.exercises.first.id,
            repetitions: 100,
            deviceId: 'FT',
            completedAt: DateTime.now())),
        throwsA(isA<FileSystemException>()));
    expect(await repo.fetchResults(), isEmpty);
  });
}

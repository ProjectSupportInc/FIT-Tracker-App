import 'package:flutter_test/flutter_test.dart';
import 'package:repform_app/features/workouts/domain/workout_models.dart';
import 'package:repform_app/features/workouts/domain/workout_policy.dart';

void main() {
  const policy = WorkoutPolicy();
  final today = DateTime(2026, 11, 9);
  const firstExercise = ExercisePlan(
      id: 'curl',
      name: 'Curl',
      kind: 'curl',
      targetReps: 5,
      coachTip: 'Slow and steady');
  const secondExercise = ExercisePlan(
      id: 'push',
      name: 'Push-up',
      kind: 'pushup',
      targetReps: 4,
      coachTip: 'Stay straight');
  final yesterday = WorkoutPlan(
      id: 'y',
      title: 'Yesterday',
      description: '',
      scheduledAt: DateTime(2026, 11, 8),
      exercises: const [firstExercise]);
  final first = WorkoutPlan(
      id: 'a',
      title: 'Today A',
      description: '',
      scheduledAt: DateTime(2026, 11, 9, 18),
      exercises: const [firstExercise, secondExercise]);
  final second = WorkoutPlan(
      id: 'b',
      title: 'Today B',
      description: '',
      scheduledAt: DateTime(2026, 11, 9, 20),
      exercises: const [firstExercise]);
  final tomorrow = WorkoutPlan(
      id: 'c',
      title: 'Future',
      description: '',
      scheduledAt: DateTime(2026, 11, 10),
      exercises: const [firstExercise]);
  final workouts = [yesterday, first, second, tomorrow];

  test('Missed yesterday never blocks the first workout today', () {
    expect(policy.availability(yesterday, workouts, {}, today),
        WorkoutAvailability.missed);
    expect(policy.availability(first, workouts, {}, today),
        WorkoutAvailability.ready);
  });

  test('Later workouts on the same day stay locked', () {
    expect(policy.availability(second, workouts, {}, today),
        WorkoutAvailability.locked);
  });

  test('Completing previous exercises unlocks later exercises and workouts',
      () {
    final results = <String, ExerciseResult>{
      'a:curl': ExerciseResult(
          workoutId: 'a',
          exerciseId: 'curl',
          repetitions: 7,
          deviceId: 'FitTrackerIOT-01',
          completedAt: today),
    };
    expect(policy.exerciseUnlocked(first, secondExercise, results), isTrue);
    expect(policy.availability(second, workouts, results, today),
        WorkoutAvailability.locked);
    results['a:push'] = ExerciseResult(
        workoutId: 'a',
        exerciseId: 'push',
        repetitions: 4,
        deviceId: 'FitTrackerIOT-01',
        completedAt: today);
    expect(policy.availability(second, workouts, results, today),
        WorkoutAvailability.ready);
  });

  test('Reps can exceed target, but falling short does not complete', () {
    expect(policy.targetReached(firstExercise, 3), isFalse);
    expect(policy.targetReached(firstExercise, 5), isTrue);
    expect(policy.targetReached(firstExercise, 12), isTrue);
  });

  test('Future workouts are not actionable', () {
    expect(policy.availability(tomorrow, workouts, {}, today),
        WorkoutAvailability.upcoming);
  });
}

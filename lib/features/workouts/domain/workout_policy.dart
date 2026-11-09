import '../../../core/utils/date_labels.dart';
import 'workout_models.dart';

enum WorkoutAvailability { completed, ready, locked, missed, upcoming }

/// Pure business rules, independent of widgets, BLE, and storage.
class WorkoutPolicy {
  const WorkoutPolicy();

  bool exerciseCompleted(
    WorkoutPlan workout,
    ExercisePlan exercise,
    Map<String, ExerciseResult> results,
  ) => results.containsKey(exerciseKey(workout, exercise));

  bool workoutCompleted(WorkoutPlan workout, Map<String, ExerciseResult> results) =>
      workout.exercises.every((exercise) => exerciseCompleted(workout, exercise, results));

  WorkoutAvailability availability(
    WorkoutPlan workout,
    List<WorkoutPlan> allWorkouts,
    Map<String, ExerciseResult> results,
    DateTime today,
  ) {
    if (workoutCompleted(workout, results)) return WorkoutAvailability.completed;
    final day = DateTime(workout.scheduledAt.year, workout.scheduledAt.month, workout.scheduledAt.day);
    final now = DateTime(today.year, today.month, today.day);
    if (day.isBefore(now)) return WorkoutAvailability.missed;
    if (day.isAfter(now)) return WorkoutAvailability.upcoming;

    // Previous-day workouts never block the next day's workouts.
    for (final previous in allWorkouts) {
      if (previous.id == workout.id) break;
      if (isSameDate(previous.scheduledAt, workout.scheduledAt) &&
          !workoutCompleted(previous, results)) {
        return WorkoutAvailability.locked;
      }
    }
    return WorkoutAvailability.ready;
  }

  bool exerciseUnlocked(
    WorkoutPlan workout,
    ExercisePlan exercise,
    Map<String, ExerciseResult> results,
  ) {
    final index = workout.exercises.indexWhere((item) => item.id == exercise.id);
    if (index < 0) return false;
    for (var i = 0; i < index; i++) {
      if (!exerciseCompleted(workout, workout.exercises[i], results)) return false;
    }
    return true;
  }

  bool targetReached(ExercisePlan exercise, int repetitions) =>
      repetitions >= exercise.targetReps;
}

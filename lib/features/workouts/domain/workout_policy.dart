// Enforces workout date/order, exercise order, and repetition-target rules without UI dependencies.
// Read docs/BEGINNER_GUIDE.md for the app flow and Dart syntax explanations.
// Imported by:
// - lib/features/home/presentation/today_screen.dart
// - lib/features/workouts/presentation/workout_card.dart
// - lib/features/workouts/presentation/workout_view_model.dart
// - lib/features/workouts/presentation/workouts_screen.dart

import '../../../core/utils/date_labels.dart';
import 'workout_models.dart';

/// Possible workout statuses returned by WorkoutPolicy and rendered by WorkoutCard.
enum WorkoutAvailability { completed, ready, locked, missed, upcoming }

/// Pure business rules, independent of widgets, BLE, and storage.
/// Rules used by WorkoutViewModel; unit tests call these methods directly without Flutter widgets.
class WorkoutPolicy {
  /// Creates WorkoutPolicy; required arguments supply its dependencies or display data.
  const WorkoutPolicy();

  /// Checks the result map for this exercise; used by workoutCompleted(), exerciseUnlocked(), and the controller.
  bool exerciseCompleted(
    WorkoutPlan workout,
    ExercisePlan exercise,
    Map<String, ExerciseResult> results,
  ) =>
      results.containsKey(exerciseKey(workout, exercise));

  /// Checks every exercise for a saved result; used by availability() and WorkoutViewModel.workoutComplete().
  bool workoutCompleted(
          WorkoutPlan workout, Map<String, ExerciseResult> results) =>
      workout.exercises
          .every((exercise) => exerciseCompleted(workout, exercise, results));

  /// Determines completed/ready/locked/missed/upcoming status; called by WorkoutViewModel.status().
  WorkoutAvailability availability(
    WorkoutPlan workout,
    List<WorkoutPlan> allWorkouts,
    Map<String, ExerciseResult> results,
    DateTime today,
  ) {
    if (workoutCompleted(workout, results)) {
      return WorkoutAvailability.completed;
    }
    // Calendar date used for comparison or one generated day in the week selector.
    final day = DateTime(workout.scheduledAt.year, workout.scheduledAt.month,
        workout.scheduledAt.day);
    // Today normalized to midnight so availability compares dates rather than clock times.
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

  /// Checks that earlier exercises are complete; used for detail buttons and startExercise() validation.
  bool exerciseUnlocked(
    WorkoutPlan workout,
    ExercisePlan exercise,
    Map<String, ExerciseResult> results,
  ) {
    // Position of the exercise in the workout; used to find previous or next exercises.
    final index =
        workout.exercises.indexWhere((item) => item.id == exercise.id);
    if (index < 0) return false;
    for (var i = 0; i < index; i++) {
      if (!exerciseCompleted(workout, workout.exercises[i], results)) {
        return false;
      }
    }
    return true;
  }

  /// Checks repetitions against the target; called by WorkoutViewModel.finishExercise().
  bool targetReached(ExercisePlan exercise, int repetitions) =>
      repetitions >= exercise.targetReps;
}

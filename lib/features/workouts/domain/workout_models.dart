// Defines workout plans, exercise plans, saved results, and their shared lookup key.
// Read docs/BEGINNER_GUIDE.md for the app flow and Dart syntax explanations.
// Imported by:
// - lib/features/workouts/data/demo_workout_repository.dart
// - lib/features/workouts/data/workout_repository.dart
// - lib/features/workouts/domain/workout_policy.dart
// - lib/features/workouts/presentation/calibration_screen.dart
// - lib/features/workouts/presentation/exercise_complete_screen.dart
// - lib/features/workouts/presentation/exercise_setup_screen.dart
// - lib/features/workouts/presentation/live_exercise_screen.dart
// - lib/features/workouts/presentation/workout_card.dart
// - lib/features/workouts/presentation/workout_detail_screen.dart
// - lib/features/workouts/presentation/workout_view_model.dart
// - lib/features/workouts/presentation/workouts_screen.dart

/// One prescribed movement, created by the demo repository and passed through exercise screens.
class ExercisePlan {
  /// Creates ExercisePlan; required arguments supply its dependencies or display data.
  const ExercisePlan({
    required this.id,
    required this.name,
    required this.kind,
    required this.targetReps,
    required this.coachTip,
  });

  /// Stable identifier used for lookups and comparisons; display labels may change independently.
  final String id;

  /// Human-readable exercise name shown throughout the workout flow.
  final String name;

  /// Movement identifier sent to the tracker and included in calibration keys.
  final String kind;

  /// Minimum repetitions required to finish this exercise.
  final int targetReps;

  /// Instructional text displayed during exercise setup.
  final String coachTip;
}

/// A scheduled, ordered list of exercises used by the policy, controller, and workout screens.
class WorkoutPlan {
  /// Creates WorkoutPlan; required arguments supply its dependencies or display data.
  const WorkoutPlan({
    required this.id,
    required this.title,
    required this.description,
    required this.scheduledAt,
    required this.exercises,
  });

  /// Stable identifier used for lookups and comparisons; display labels may change independently.
  final String id;

  /// Title displayed by this component or workout.
  final String title;

  /// Workout description displayed on the details page.
  final String description;

  /// Scheduled date/time used for availability, grouping, and time labels.
  final DateTime scheduledAt;

  /// Ordered exercises; earlier ones must be completed before later ones unlock.
  final List<ExercisePlan> exercises;
}

/// Saved completion record created by finishExercise() and displayed in completion/history screens.
class ExerciseResult {
  /// Creates ExerciseResult; required arguments supply its dependencies or display data.
  const ExerciseResult({
    required this.workoutId,
    required this.exerciseId,
    required this.repetitions,
    required this.deviceId,
    required this.completedAt,
  });

  /// ID of the workout to which this saved result belongs.
  final String workoutId;

  /// ID of the exercise to which this saved result belongs.
  final String exerciseId;

  /// Actual saved rep total, including reps above the target.
  final int repetitions;

  /// Identifier of the tracker used to record this result.
  final String deviceId;

  /// Timestamp recorded when the result was created.
  final DateTime completedAt;

  /// Workout:exercise identifier used to index saved results.
  String get key => '$workoutId:$exerciseId';
}

/// Combines workout/exercise IDs for result lookups in WorkoutPolicy and WorkoutViewModel.
String exerciseKey(WorkoutPlan workout, ExercisePlan exercise) =>
    '${workout.id}:${exercise.id}';

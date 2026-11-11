// Defines how the workout controller loads plans/results and saves a completed exercise.
// Read docs/BEGINNER_GUIDE.md for the app flow and Dart syntax explanations.
// Imported by:
// - lib/features/workouts/data/demo_workout_repository.dart
// - lib/features/workouts/presentation/workout_view_model.dart

import '../domain/workout_models.dart';

/// Storage contract consumed by WorkoutViewModel; DemoWorkoutRepository currently implements it.
abstract class WorkoutRepository {
  /// Returns available plans to WorkoutViewModel.load(); the demo returns an unmodifiable list.
  Future<List<WorkoutPlan>> fetchWorkouts();

  /// Returns saved results to WorkoutViewModel.load(); the demo returns an unmodifiable map.
  Future<Map<String, ExerciseResult>> fetchResults();

  /// Stores one completion record; called by WorkoutViewModel.finishExercise().
  Future<void> saveResult(ExerciseResult result);
}

// Defines how the workout controller loads plans/results and saves a completed exercise.
// Read docs/BEGINNER_GUIDE.md for the app flow and Dart syntax explanations.
// Imported by:
// - lib/features/workouts/data/demo_workout_repository.dart
// - lib/features/workouts/presentation/workout_view_model.dart

import '../domain/workout_models.dart';
import '../domain/workout_journal.dart';

/// Storage contract consumed by WorkoutViewModel; normal launches use local storage.
abstract class WorkoutRepository {
  // In-memory defaults support demo/test adapters; durable storage overrides these.
  WorkoutJournal _journal = const WorkoutJournal();
  Future<WorkoutJournal> readJournal() async => _journal;
  Future<void> writeJournal(WorkoutJournal value) async {
    _journal = value;
  }

  Future<List<ExerciseResult>> fetchHistory() async =>
      (await fetchResults()).values.toList();
  Future<void> commitResult(
      ExerciseResult result, WorkoutJournal journal) async {
    await saveResult(result);
    await writeJournal(journal);
  }

  /// Returns available plans to WorkoutViewModel.load(); the demo returns an unmodifiable list.
  Future<List<WorkoutPlan>> fetchWorkouts();

  /// Returns saved results to WorkoutViewModel.load(); the demo returns an unmodifiable map.
  Future<Map<String, ExerciseResult>> fetchResults();

  /// Stores one completion record; called by WorkoutViewModel.finishExercise().
  Future<void> saveResult(ExerciseResult result);
}

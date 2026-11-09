import '../domain/workout_models.dart';

abstract class WorkoutRepository {
  Future<List<WorkoutPlan>> fetchWorkouts();
  Future<Map<String, ExerciseResult>> fetchResults();
  Future<void> saveResult(ExerciseResult result);
}

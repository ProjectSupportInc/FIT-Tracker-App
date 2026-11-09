class ExercisePlan {
  const ExercisePlan({
    required this.id,
    required this.name,
    required this.kind,
    required this.targetReps,
    required this.coachTip,
  });
  final String id;
  final String name;
  final String kind;
  final int targetReps;
  final String coachTip;
}

class WorkoutPlan {
  const WorkoutPlan({
    required this.id,
    required this.title,
    required this.description,
    required this.scheduledAt,
    required this.exercises,
  });
  final String id;
  final String title;
  final String description;
  final DateTime scheduledAt;
  final List<ExercisePlan> exercises;
}

class ExerciseResult {
  const ExerciseResult({
    required this.workoutId,
    required this.exerciseId,
    required this.repetitions,
    required this.deviceId,
    required this.completedAt,
  });
  final String workoutId;
  final String exerciseId;
  final int repetitions;
  final String deviceId;
  final DateTime completedAt;

  String get key => '$workoutId:$exerciseId';
}

String exerciseKey(WorkoutPlan workout, ExercisePlan exercise) =>
    '${workout.id}:${exercise.id}';

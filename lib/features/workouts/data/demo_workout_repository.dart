import '../domain/workout_models.dart';
import 'workout_repository.dart';

/// In-memory sample data. Replace with an authenticated backend repository.
class DemoWorkoutRepository implements WorkoutRepository {
  final Map<String, ExerciseResult> _results = {};
  late final List<WorkoutPlan> _plans = _buildPlans();

  List<WorkoutPlan> _buildPlans() {
    final today = DateTime.now();
    DateTime when(int dayOffset, int hour, int minute) =>
        DateTime(today.year, today.month, today.day + dayOffset, hour, minute);
    const curl = ExercisePlan(id: 'curl', name: 'Dumbbell Curl', kind: 'dumbbell curl',
      targetReps: 5, coachTip: 'Keep your elbows close to your body.');
    const pushUps = ExercisePlan(id: 'pushups', name: 'Push-ups', kind: 'push-ups',
      targetReps: 4, coachTip: 'Maintain a straight body line.');
    const bench = ExercisePlan(id: 'bench', name: 'Bench Press', kind: 'bench press',
      targetReps: 8, coachTip: 'Keep the movement controlled.');
    const shoulder = ExercisePlan(id: 'shoulder', name: 'Shoulder Press', kind: 'shoulder press',
      targetReps: 6, coachTip: 'Avoid arching your lower back.');
    const row = ExercisePlan(id: 'row', name: 'Dumbbell Row', kind: 'dumbbell row',
      targetReps: 8, coachTip: 'Keep your back steady.');
    const squat = ExercisePlan(id: 'squat', name: 'Squats', kind: 'squat',
      targetReps: 10, coachTip: 'Keep your knees tracking with your toes.');

    final plans = <WorkoutPlan>[
      WorkoutPlan(id: 'w0', title: 'Foundation Session', description: 'Every strong habit has a beginning.',
        scheduledAt: when(-1, 16, 30), exercises: const [row]),
      WorkoutPlan(id: 'w1', title: 'Upper Body Focus', description: 'Form first. Strength follows.',
        scheduledAt: when(0, 18, 0), exercises: const [curl, pushUps]),
      WorkoutPlan(id: 'w2', title: 'Push Your Limits', description: 'One deliberate rep at a time.',
        scheduledAt: when(0, 20, 0), exercises: const [bench, shoulder]),
      WorkoutPlan(id: 'w3', title: 'Full Body Energy', description: 'A stronger finish to the week.',
        scheduledAt: when(2, 7, 0), exercises: const [squat, row]),
    ];
    // One completed workout yesterday, matching the V4 sample history.
    final finished = ExerciseResult(workoutId: 'w0', exerciseId: 'row',
      repetitions: 10, deviceId: 'FitTrackerIOT-01', completedAt: when(-1, 16, 45));
    _results[finished.key] = finished;
    return plans..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
  }

  @override
  Future<List<WorkoutPlan>> fetchWorkouts() async => List.unmodifiable(_plans);

  @override
  Future<Map<String, ExerciseResult>> fetchResults() async => Map.unmodifiable(_results);

  @override
  Future<void> saveResult(ExerciseResult result) async {
    _results[result.key] = result;
  }
}

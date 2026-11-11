// Builds sample workouts around the current date and stores results only in memory.
// Read docs/BEGINNER_GUIDE.md for the app flow and Dart syntax explanations.
// Imported by:
// - lib/app/fittracker_app.dart

import '../domain/workout_models.dart';
import 'workout_repository.dart';

/// In-memory sample data. Replace with an authenticated backend repository.
/// In-memory storage selected in FitTrackerApp; changes disappear when the app restarts.
class DemoWorkoutRepository implements WorkoutRepository {
  /// An injectable date keeps local schedules and tests deterministic.
  DemoWorkoutRepository({DateTime? today}) : _today = today ?? DateTime.now();
  final DateTime _today;

  /// Results stored by workout:exercise key; used for completion checks and progress history.
  final Map<String, ExerciseResult> _results = {};

  /// Sample plans initialized on first access by _buildPlans().
  late final List<WorkoutPlan> _plans = _buildPlans();

  /// Creates dated demo plans and seeds yesterday’s result; lazily called to initialize _plans.
  List<WorkoutPlan> _buildPlans() {
    // Current date used for today’s grouping, calendar labels, or relative sample data.
    final today = _today;
    // Local helper in _buildPlans(): constructs sample times relative to today using dayOffset/hour/minute.
    DateTime when(int dayOffset, int hour, int minute) =>
        DateTime(today.year, today.month, today.day + dayOffset, hour, minute);
    // Sample dumbbell-curl prescription used in the demo plan.
    const curl = ExercisePlan(
        id: 'curl',
        name: 'Dumbbell Curl',
        kind: 'dumbbell curl',
        targetReps: 5,
        coachTip: 'Keep your elbows close to your body.');
    // Sample push-up prescription used in the demo plan.
    const pushUps = ExercisePlan(
        id: 'pushups',
        name: 'Push-ups',
        kind: 'push-ups',
        targetReps: 4,
        coachTip: 'Maintain a straight body line.');
    // Sample bench-press prescription used in the demo plan.
    const bench = ExercisePlan(
        id: 'bench',
        name: 'Bench Press',
        kind: 'bench press',
        targetReps: 8,
        coachTip: 'Keep the movement controlled.');
    // Sample shoulder-press prescription used in the demo plan.
    const shoulder = ExercisePlan(
        id: 'shoulder',
        name: 'Shoulder Press',
        kind: 'shoulder press',
        targetReps: 6,
        coachTip: 'Avoid arching your lower back.');
    // Sample dumbbell-row prescription reused across demo plans.
    const row = ExercisePlan(
        id: 'row',
        name: 'Dumbbell Row',
        kind: 'dumbbell row',
        targetReps: 8,
        coachTip: 'Keep your back steady.');
    // Sample squat prescription used in the demo plan.
    const squat = ExercisePlan(
        id: 'squat',
        name: 'Squats',
        kind: 'squat',
        targetReps: 10,
        coachTip: 'Keep your knees tracking with your toes.');

    // Demo plan list returned in scheduled order.
    final plans = <WorkoutPlan>[
      WorkoutPlan(
          id: 'w0',
          title: 'Foundation Session',
          description: 'Every strong habit has a beginning.',
          scheduledAt: when(-1, 16, 30),
          exercises: const [row]),
      WorkoutPlan(
          id: 'w1',
          title: 'Upper Body Focus',
          description: 'Form first. Strength follows.',
          scheduledAt: when(0, 18, 0),
          exercises: const [curl, pushUps]),
      WorkoutPlan(
          id: 'w2',
          title: 'Push Your Limits',
          description: 'One deliberate rep at a time.',
          scheduledAt: when(0, 20, 0),
          exercises: const [bench, shoulder]),
      WorkoutPlan(
          id: 'w3',
          title: 'Full Body Energy',
          description: 'A stronger finish to the week.',
          scheduledAt: when(2, 7, 0),
          exercises: const [squat, row]),
    ];
    // One completed workout yesterday, matching the V4 sample history.
    // Yesterday’s seeded demo completion, inserted into _results.
    final finished = ExerciseResult(
        workoutId: 'w0',
        exerciseId: 'row',
        repetitions: 10,
        deviceId: 'FitTrackerIOT-01',
        completedAt: when(-1, 16, 45));
    _results[finished.key] = finished;
    return plans..sort((a, b) => a.scheduledAt.compareTo(b.scheduledAt));
  }

  /// Returns available plans to WorkoutViewModel.load(); the demo returns an unmodifiable list.
  @override
  Future<List<WorkoutPlan>> fetchWorkouts() async => List.unmodifiable(_plans);

  /// Returns saved results to WorkoutViewModel.load(); the demo returns an unmodifiable map.
  @override
  Future<Map<String, ExerciseResult>> fetchResults() async =>
      Map.unmodifiable(_results);

  /// Stores one completion record; called by WorkoutViewModel.finishExercise().
  @override
  Future<void> saveResult(ExerciseResult result) async {
    _results[result.key] = result;
  }
}

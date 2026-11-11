// Shows the saved result and opens the next exercise or returns to workout details.
// Read docs/BEGINNER_GUIDE.md for the app flow and Dart syntax explanations.
// Imported by:
// - lib/features/workouts/presentation/live_exercise_screen.dart

import 'package:flutter/material.dart';

import '../../../app/app_services.dart';
import '../../../app/fittracker_theme.dart';
import '../../../core/widgets/fit_widgets.dart';
import '../domain/workout_models.dart';
import 'exercise_setup_screen.dart';

/// Replaces LiveExerciseScreen after saving; shows the result and routes to the next exercise.
class ExerciseCompleteScreen extends StatelessWidget {
  /// Creates ExerciseCompleteScreen; required arguments supply its dependencies or display data.
  const ExerciseCompleteScreen(
      {super.key, required this.workout, required this.exercise});

  /// Selected workout supplied by the previous screen.
  final WorkoutPlan workout;

  /// Selected exercise supplied by the previous screen.
  final ExercisePlan exercise;

  /// Flutter calls this to describe the UI. context locates services/theme/navigation above this widget.
  @override
  Widget build(BuildContext context) {
    // Shared view model (controller); this screen reads its state and calls its actions.
    final vm = AppServices.of(context).workouts;
    // Saved result for this exercise; null if no completion record exists.
    final result = vm.resultFor(workout, exercise);
    // Position of the exercise in the workout; used to find previous or next exercises.
    final index =
        workout.exercises.indexWhere((item) => item.id == exercise.id);
    // Next exercise after the completed one; null at the end of the workout.
    final next = index >= 0 && index + 1 < workout.exercises.length
        ? workout.exercises[index + 1]
        : null;
    // Whether all exercises are saved; chooses the completion-page headline.
    final workoutDone = vm.workoutComplete(workout);
    return Scaffold(
      appBar: AppBar(
          automaticallyImplyLeading: false,
          title: const Text('Exercise Complete')),
      body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(children: [
            const Spacer(),
            const CircleAvatar(
                radius: 57,
                backgroundColor: FitColors.lime,
                child:
                    Icon(Icons.check_rounded, size: 63, color: FitColors.ink)),
            const SizedBox(height: 24),
            SectionHeading(workoutDone ? 'Workout completed!' : 'Nice work!',
                subtitle: 'Your effort is recorded.'),
            const SizedBox(height: 25),
            FitCard(
                child: Column(children: [
              Text(exercise.name,
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              Text('${result?.repetitions ?? 0}',
                  style: const TextStyle(
                      fontSize: 65, fontWeight: FontWeight.w900)),
              Text('reps completed · target ${exercise.targetReps}'),
            ])),
            const Spacer(),
            if (next != null)
              AccentButton('Next: ${next.name}',
                  icon: Icons.arrow_forward,
                  onPressed: () => Navigator.of(context).pushReplacement(
                      MaterialPageRoute<void>(
                          builder: (_) => ExerciseSetupScreen(
                              workout: workout, exercise: next))))
            else
              AccentButton('Back to workout',
                  icon: Icons.check, onPressed: () => Navigator.pop(context)),
            const SizedBox(height: 12),
            if (next != null)
              OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Back to workout')),
          ])),
    );
  }
}

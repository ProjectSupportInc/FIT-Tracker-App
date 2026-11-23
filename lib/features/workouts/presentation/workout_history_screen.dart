import 'package:flutter/material.dart';

import '../../../app/app_services.dart';
import '../../../core/utils/date_labels.dart';
import '../../../core/widgets/fit_widgets.dart';
import '../domain/workout_models.dart';
import 'exercise_setup_screen.dart';

/// Repeat is a secondary action on results; previous attempts are kept.
Future<void> confirmRepeat(BuildContext context, WorkoutPlan workout,
    {ExercisePlan? exercise}) async {
  final vm = AppServices.of(context).workouts;
  final confirmed = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => SafeArea(
        child: SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Repeat ${exercise?.name ?? workout.title}?',
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 16),
            Text(exercise == null
                ? 'Start a fresh attempt from the first exercise. Your earlier results and today’s completion stay saved.'
                : 'Start a fresh attempt of this exercise. Your previous results and the other exercises stay saved.'),
            const SizedBox(height: 24),
            AccentButton('Start new attempt',
                onPressed: () => Navigator.pop(context, true)),
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Keep current results')),
          ]),
    )),
  );
  if (confirmed != true || !context.mounted) return;
  try {
    await vm.beginRepeat(workout, exercise: exercise);
    if (!context.mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => ExerciseSetupScreen(
            workout: workout, exercise: exercise ?? workout.exercises.first)));
  } catch (error) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('$error')));
    }
  }
}

class WorkoutHistoryScreen extends StatelessWidget {
  const WorkoutHistoryScreen({super.key, required this.workout, this.exercise});
  final WorkoutPlan workout;
  final ExercisePlan? exercise;

  @override
  Widget build(BuildContext context) {
    final vm = AppServices.of(context).workouts;
    return AnimatedBuilder(
        animation: vm,
        builder: (context, _) {
          final attempts = vm.historyFor(workout, exercise);
          return Scaffold(
            appBar: AppBar(title: const Text('Your results'), actions: [
              if (vm.canRepeat(workout) &&
                  (exercise == null || vm.exerciseComplete(workout, exercise!)))
                PopupMenuButton<String>(
                    tooltip: 'Result options',
                    onSelected: (_) =>
                        confirmRepeat(context, workout, exercise: exercise),
                    itemBuilder: (_) => [
                          PopupMenuItem(
                              value: 'repeat',
                              child: Text(exercise == null
                                  ? 'Repeat workout'
                                  : 'Repeat exercise'))
                        ]),
            ]),
            body: ListView(padding: const EdgeInsets.all(24), children: [
              SectionHeading(exercise?.name ?? workout.title,
                  subtitle: 'Every attempt stays in your history.'),
              const SizedBox(height: 24),
              if (attempts.isEmpty) const Text('No attempts recorded yet.'),
              for (final result in attempts) ...[
                FitCard(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      if (exercise == null)
                        Text(
                            workout.exercises
                                .firstWhere((e) => e.id == result.exerciseId)
                                .name,
                            style: Theme.of(context).textTheme.titleMedium),
                      Text('${result.repetitions} reps',
                          style: Theme.of(context).textTheme.headlineSmall),
                      const SizedBox(height: 8),
                      Text(
                          '${shortDate(result.completedAt)} · ${friendlyTime(result.completedAt)}'),
                      const SizedBox(height: 10),
                      FitBadge(
                          result.completed
                              ? 'Completed'
                              : 'Interrupted · last confirmed count',
                          icon: result.completed
                              ? Icons.check_circle_outline
                              : Icons.pause_circle_outline),
                    ])),
                const SizedBox(height: 12),
              ],
            ]),
          );
        });
  }
}

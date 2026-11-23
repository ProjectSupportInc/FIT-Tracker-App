// Lists a workout’s ordered exercises and opens setup for an unlocked unfinished exercise.
// Read docs/BEGINNER_GUIDE.md for the app flow and Dart syntax explanations.
// Imported by:
// - lib/features/home/presentation/today_screen.dart
// - lib/features/workouts/presentation/workouts_screen.dart

import 'package:flutter/material.dart';

import '../../../app/app_services.dart';
import '../../../app/fittracker_theme.dart';
import '../../../core/utils/date_labels.dart';
import '../../../core/widgets/fit_widgets.dart';
import '../domain/workout_models.dart';
import 'exercise_setup_screen.dart';
import 'workout_view_model.dart';
import 'workout_history_screen.dart';
import 'exercise_illustration.dart';

/// Route opened by TodayScreen/WorkoutsScreen; passes the selected plan to ExerciseSetupScreen.
class WorkoutDetailScreen extends StatelessWidget {
  /// Creates WorkoutDetailScreen; required arguments supply its dependencies or display data.
  const WorkoutDetailScreen({super.key, required this.workout});

  /// Selected workout supplied by the previous screen.
  final WorkoutPlan workout;

  /// Flutter calls this to describe the UI. context locates services/theme/navigation above this widget.
  @override
  Widget build(BuildContext context) {
    // Shared view model (controller); this screen reads its state and calls its actions.
    final vm = AppServices.of(context).workouts;
    return AnimatedBuilder(
        animation: vm,
        builder: (context, _) {
          // Number of saved exercises used in the completion fraction and progress bar.
          final completed = vm.doneCount(workout);
          return Scaffold(
            appBar: AppBar(title: const Text('Workout Details'), actions: [
              PopupMenuButton<String>(
                  tooltip: 'Workout options',
                  onSelected: (action) {
                    if (action == 'repeat') {
                      confirmRepeat(context, workout);
                    } else {
                      Navigator.of(context).push(MaterialPageRoute<void>(
                          builder: (_) =>
                              WorkoutHistoryScreen(workout: workout)));
                    }
                  },
                  itemBuilder: (_) => [
                        const PopupMenuItem(
                            value: 'history', child: Text('View history')),
                        if (vm.canRepeat(workout) && vm.doneCount(workout) > 0)
                          const PopupMenuItem(
                              value: 'repeat', child: Text('Repeat workout')),
                      ]),
            ]),
            body: ListView(
                padding: const EdgeInsets.fromLTRB(22, 12, 22, 26),
                children: [
                  SectionHeading(workout.title, subtitle: workout.description),
                  const SizedBox(height: 16),
                  FitBadge(
                      '${shortDate(workout.scheduledAt)} · ${friendlyTime(workout.scheduledAt)}',
                      icon: Icons.calendar_month_outlined),
                  const SizedBox(height: 24),
                  FitCard(
                      child: Row(children: [
                    const Icon(Icons.bolt, size: 32, color: FitColors.peach),
                    const SizedBox(width: 15),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text(
                              '$completed/${workout.exercises.length} exercises completed',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w800)),
                          const SizedBox(height: 8),
                          LinearProgressIndicator(
                              value: completed / workout.exercises.length,
                              minHeight: 8,
                              borderRadius: BorderRadius.circular(10)),
                        ])),
                  ])),
                  if (vm.repeat?.workoutId == workout.id &&
                      !vm.hasActiveSession) ...[
                    const SizedBox(height: 18),
                    FitCard(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                          Text('Repeat in progress',
                              style: Theme.of(context).textTheme.titleMedium),
                          Text(
                              'Exercise ${vm.repeat!.index + 1} of ${vm.repeat!.exerciseIds.length}'),
                          const SizedBox(height: 12),
                          AccentButton('Continue repeat',
                              onPressed: () => Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                      builder: (_) => ExerciseSetupScreen(
                                          workout: workout,
                                          exercise: workout.exercises
                                              .firstWhere((e) =>
                                                  e.id ==
                                                  vm.repeat!.exerciseId))))),
                          TextButton(
                              onPressed: () async {
                                try {
                                  await vm.cancelRepeat();
                                } catch (error) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('$error')));
                                  }
                                }
                              },
                              child: const Text('End repeat')),
                        ])),
                  ],
                  const SizedBox(height: 27),
                  const Text('Your exercise sequence',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 15),
                  for (var i = 0; i < workout.exercises.length; i++) ...[
                    _exerciseTile(context, i, workout.exercises[i], vm),
                    const SizedBox(height: 12),
                  ],
                  if (vm.workoutComplete(workout)) ...[
                    const SizedBox(height: 8),
                    const FitBadge('Workout completed!',
                        highlight: true, icon: Icons.check_circle),
                  ],
                ]),
          );
        });
  }

  /// Builds one exercise row; build() calls it for each exercise with its index and controller.
  Widget _exerciseTile(BuildContext context, int index, ExercisePlan exercise,
      WorkoutViewModel vm) {
    // Whether this row’s exercise already has a saved result.
    final finished = vm.exerciseComplete(workout, exercise);
    // Whether all earlier exercises are complete.
    final unlocked = vm.exerciseUnlocked(workout, exercise);
    // Whether an exercise row can be opened: unlocked and not already finished.
    final enabled =
        unlocked && !finished && vm.isToday(workout) && !vm.hasActiveSession;
    // Saved result for this exercise; null if no completion record exists.
    final result = vm.resultFor(workout, exercise);
    return Opacity(
      opacity: enabled ? 1 : .57,
      child: FitCard(
        onTap: finished
            ? () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) =>
                    WorkoutHistoryScreen(workout: workout, exercise: exercise)))
            : enabled
                ? () => Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => ExerciseSetupScreen(
                        workout: workout, exercise: exercise)))
                : null,
        child: Row(children: [
          CircleAvatar(
            backgroundColor: enabled
                ? FitColors.lime
                : Theme.of(context).colorScheme.surfaceContainerHighest,
            child: finished
                ? const Icon(Icons.check, color: FitColors.ink)
                : unlocked
                    ? ExerciseIllustration(
                        kind: exercise.kind, size: 34, color: FitColors.ink)
                    : const Icon(Icons.lock_outline, size: 18),
          ),
          const SizedBox(width: 14),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(exercise.name,
                    style: const TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 5),
                Text(
                    finished
                        ? '${result?.repetitions} completed · target ${exercise.targetReps}'
                        : 'Target ${exercise.targetReps} reps',
                    style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ])),
          if (!finished && vm.historyFor(workout, exercise).isNotEmpty)
            IconButton(
                tooltip: 'Exercise history',
                icon: const Icon(Icons.history),
                onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                        builder: (_) => WorkoutHistoryScreen(
                            workout: workout, exercise: exercise)))),
          Icon(finished
              ? Icons.check_circle_outline
              : enabled
                  ? Icons.chevron_right
                  : Icons.lock_outline),
        ]),
      ),
    );
  }
}

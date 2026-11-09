import 'package:flutter/material.dart';

import '../../../app/app_services.dart';
import '../../../app/fittracker_theme.dart';
import '../../../core/utils/date_labels.dart';
import '../../../core/widgets/fit_widgets.dart';
import '../domain/workout_models.dart';
import 'exercise_setup_screen.dart';
import 'workout_view_model.dart';

class WorkoutDetailScreen extends StatelessWidget {
  const WorkoutDetailScreen({super.key, required this.workout});
  final WorkoutPlan workout;

  @override
  Widget build(BuildContext context) {
    final vm = AppServices.of(context).workouts;
    return AnimatedBuilder(animation: vm, builder: (context, _) {
      final completed = vm.doneCount(workout);
      return Scaffold(
        appBar: AppBar(title: const Text('Workout Details')),
        body: ListView(padding: const EdgeInsets.fromLTRB(22, 12, 22, 26), children: [
          SectionHeading(workout.title, subtitle: workout.description),
          const SizedBox(height: 16),
          FitBadge('${shortDate(workout.scheduledAt)} · ${friendlyTime(workout.scheduledAt)}',
              icon: Icons.calendar_month_outlined),
          const SizedBox(height: 24),
          FitCard(child: Row(children: [
            const Icon(Icons.bolt, size: 32, color: FitColors.peach),
            const SizedBox(width: 15),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('$completed/${workout.exercises.length} exercises completed',
                  style: const TextStyle(fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              LinearProgressIndicator(value: completed / workout.exercises.length,
                  minHeight: 8, borderRadius: BorderRadius.circular(10)),
            ])),
          ])),
          const SizedBox(height: 27),
          const Text('Your exercise sequence', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 15),
          for (var i = 0; i < workout.exercises.length; i++) ...[
            _exerciseTile(context, i, workout.exercises[i], vm),
            const SizedBox(height: 12),
          ],
          if (vm.workoutComplete(workout)) ...[
            const SizedBox(height: 8),
            const FitBadge('Workout completed!', highlight: true, icon: Icons.check_circle),
          ],
        ]),
      );
    });
  }

  Widget _exerciseTile(BuildContext context, int index, ExercisePlan exercise, WorkoutViewModel vm) {
    final finished = vm.exerciseComplete(workout, exercise);
    final unlocked = vm.exerciseUnlocked(workout, exercise);
    final enabled = unlocked && !finished;
    final result = vm.resultFor(workout, exercise);
    return Opacity(opacity: enabled ? 1 : .57,
      child: FitCard(
        onTap: enabled ? () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => ExerciseSetupScreen(workout: workout, exercise: exercise))) : null,
        child: Row(children: [
          CircleAvatar(
            backgroundColor: enabled ? FitColors.lime : Theme.of(context).colorScheme.surfaceContainerHighest,
            child: finished ? const Icon(Icons.check, color: FitColors.ink)
                : unlocked ? Text('${index + 1}', style: const TextStyle(color: FitColors.ink, fontWeight: FontWeight.w900))
                : const Icon(Icons.lock_outline, size: 18),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(exercise.name, style: const TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 5),
            Text(finished ? '${result?.repetitions} completed · target ${exercise.targetReps}'
                 : 'Target ${exercise.targetReps} reps',
              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ])),
          Icon(finished ? Icons.check_circle_outline : enabled ? Icons.chevron_right : Icons.lock_outline),
        ]),
      ),
    );
  }
}

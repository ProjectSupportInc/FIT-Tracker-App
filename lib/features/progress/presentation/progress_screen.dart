import 'package:flutter/material.dart';

import '../../../app/app_services.dart';
import '../../../app/fittracker_theme.dart';
import '../../../core/utils/date_labels.dart';
import '../../../core/widgets/fit_widgets.dart';

class ProgressScreen extends StatelessWidget {
  const ProgressScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = AppServices.of(context).workouts;
    return AnimatedBuilder(animation: vm, builder: (context, _) {
      final completedWorkouts = vm.workouts.where(vm.workoutComplete).length;
      return ListView(padding: const EdgeInsets.fromLTRB(22, 18, 22, 32), children: [
        const SectionHeading('See how far you\'ve come.',
            subtitle: 'Progress is built one movement at a time.'),
        const SizedBox(height: 23),
        Row(children: [
          Expanded(child: StatTile(number: '$completedWorkouts', label: 'Workouts finished', icon: Icons.emoji_events)),
          const SizedBox(width: 12),
          Expanded(child: StatTile(number: '${vm.results.length}',
            label: 'Exercises finished', icon: Icons.fitness_center)),
        ]),
        const SizedBox(height: 28),
        const Text('Workout history', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
        const SizedBox(height: 14),
        for (final workout in vm.workouts.where((w) => vm.doneCount(w) > 0)) ...[
          FitCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Expanded(child: Text(workout.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900))),
              FitBadge(vm.workoutComplete(workout) ? 'Completed' : 'In progress',
                highlight: vm.workoutComplete(workout)),
            ]),
            const SizedBox(height: 5),
            Text(shortDate(workout.scheduledAt),
              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const Divider(height: 28),
            for (final ex in workout.exercises) ...[
              if (vm.resultFor(workout, ex) != null) ...[
                Row(children: [
                  const Icon(Icons.check_circle_outline, size: 18, color: FitColors.lime),
                  const SizedBox(width: 10),
                  Expanded(child: Text(ex.name, style: const TextStyle(fontWeight: FontWeight.w700))),
                  Text('${vm.resultFor(workout, ex)!.repetitions} / ${ex.targetReps} reps',
                    style: const TextStyle(fontWeight: FontWeight.w800)),
                ]),
                const SizedBox(height: 13),
              ],
            ],
          ])),
          const SizedBox(height: 12),
        ],
      ]);
    });
  }
}

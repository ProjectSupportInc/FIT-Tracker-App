import 'package:flutter/material.dart';

import '../../../app/fittracker_theme.dart';
import '../../../core/utils/date_labels.dart';
import '../../../core/widgets/fit_widgets.dart';
import '../domain/workout_models.dart';
import '../domain/workout_policy.dart';
import 'workout_view_model.dart';

class WorkoutCard extends StatelessWidget {
  const WorkoutCard({super.key, required this.workout, required this.vm, required this.onTap});
  final WorkoutPlan workout;
  final WorkoutViewModel vm;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final status = vm.status(workout);
    final locked = status != WorkoutAvailability.ready;
    final label = switch (status) {
      WorkoutAvailability.completed => 'Completed',
      WorkoutAvailability.ready => 'Ready today',
      WorkoutAvailability.locked => 'Locked',
      WorkoutAvailability.missed => 'Not completed',
      WorkoutAvailability.upcoming => 'Upcoming',
    };
    return Opacity(
      opacity: locked ? .56 : 1,
      child: FitCard(
        onTap: onTap,
        child: Row(children: [
          Container(
            width: 58, height: 65,
            decoration: BoxDecoration(
              color: locked ? Theme.of(context).colorScheme.surfaceContainerHighest : FitColors.lime,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(locked ? Icons.lock_outline : Icons.fitness_center,
                color: locked ? null : FitColors.ink, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(workout.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
            const SizedBox(height: 5),
            Text('${friendlyTime(workout.scheduledAt)} · ${workout.exercises.length} exercises',
                style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
            const SizedBox(height: 9),
            FitBadge(label, highlight: status == WorkoutAvailability.ready),
          ])),
          if (!locked) const Icon(Icons.chevron_right_rounded),
        ]),
      ),
    );
  }
}

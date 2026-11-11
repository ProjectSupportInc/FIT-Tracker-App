// Renders one workout summary and its availability badge in Today and Workouts.
// Read docs/BEGINNER_GUIDE.md for the app flow and Dart syntax explanations.
// Imported by:
// - lib/features/home/presentation/today_screen.dart
// - lib/features/workouts/presentation/workouts_screen.dart

import 'package:flutter/material.dart';

import '../../../app/fittracker_theme.dart';
import '../../../core/utils/date_labels.dart';
import '../../../core/widgets/fit_widgets.dart';
import '../domain/workout_models.dart';
import '../domain/workout_policy.dart';
import 'workout_view_model.dart';

/// Shared workout summary constructed by TodayScreen and WorkoutsScreen.
class WorkoutCard extends StatelessWidget {
  /// Creates WorkoutCard; required arguments supply its dependencies or display data.
  const WorkoutCard(
      {super.key,
      required this.workout,
      required this.vm,
      required this.onTap});

  /// Selected workout supplied by the previous screen.
  final WorkoutPlan workout;

  /// Shared view model (controller); this screen reads its state and calls its actions.
  final WorkoutViewModel vm;

  /// Optional card-tap callback supplied by the parent; null makes the card non-actionable.
  final VoidCallback? onTap;

  /// Flutter calls this to describe the UI. context locates services/theme/navigation above this widget.
  @override
  Widget build(BuildContext context) {
    // Workout availability returned by the controller; controls the card badge and appearance.
    final status = vm.status(workout);
    // Whether the workout is not ready today; dims the summary card.
    final locked = status != WorkoutAvailability.ready;
    // Text displayed on this badge/button/statistic or derived from workout availability.
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
            width: 58,
            height: 65,
            decoration: BoxDecoration(
              color: locked
                  ? Theme.of(context).colorScheme.surfaceContainerHighest
                  : FitColors.lime,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(locked ? Icons.lock_outline : Icons.fitness_center,
                color: locked ? null : FitColors.ink, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(workout.title,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w900)),
                const SizedBox(height: 5),
                Text(
                    '${friendlyTime(workout.scheduledAt)} · ${workout.exercises.length} exercises',
                    style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant)),
                const SizedBox(height: 9),
                FitBadge(label, highlight: status == WorkoutAvailability.ready),
              ])),
          if (!locked) const Icon(Icons.chevron_right_rounded),
        ]),
      ),
    );
  }
}

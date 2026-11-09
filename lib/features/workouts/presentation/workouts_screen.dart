import 'package:flutter/material.dart';

import '../../../app/app_services.dart';
import '../../../core/utils/date_labels.dart';
import '../../../core/widgets/fit_widgets.dart';
import '../domain/workout_models.dart';
import '../domain/workout_policy.dart';
import 'workout_card.dart';
import 'workout_detail_screen.dart';

class WorkoutsScreen extends StatelessWidget {
  const WorkoutsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = AppServices.of(context).workouts;
    return AnimatedBuilder(
      animation: vm,
      builder: (context, _) {
        if (!vm.isLoaded) return const Center(child: CircularProgressIndicator());
        final days = <String, List<WorkoutPlan>>{};
        for (final workout in vm.workouts) {
          final key = '${workout.scheduledAt.year}-${workout.scheduledAt.month}-${workout.scheduledAt.day}';
          days.putIfAbsent(key, () => []).add(workout);
        }
        return ListView(padding: const EdgeInsets.fromLTRB(22, 18, 22, 28), children: [
          const SectionHeading('Built for progress.', subtitle: 'Follow your workouts, one session at a time.'),
          const SizedBox(height: 20),
          for (final dayWorkouts in days.values) ...[
            Padding(
              padding: const EdgeInsets.only(top: 16, bottom: 13),
              child: Text(_dayHeading(dayWorkouts.first.scheduledAt),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
            ),
            for (final workout in dayWorkouts) ...[
              WorkoutCard(
                workout: workout,
                vm: vm,
                onTap: vm.status(workout) == WorkoutAvailability.ready
                    ? () => Navigator.of(context).push(MaterialPageRoute<void>(
                        builder: (_) => WorkoutDetailScreen(workout: workout)))
                    : null,
              ),
              const SizedBox(height: 12),
            ],
          ],
        ]);
      },
    );
  }

  String _dayHeading(DateTime date) {
    final today = DateTime.now();
    if (isSameDate(date, today)) return 'Today · ${shortDate(date)}';
    if (isSameDate(date, today.subtract(const Duration(days: 1)))) return 'Yesterday · ${shortDate(date)}';
    if (isSameDate(date, today.add(const Duration(days: 1)))) return 'Tomorrow · ${shortDate(date)}';
    return longDate(date);
  }
}

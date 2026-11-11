// Groups workouts by date and opens details for workouts that are ready today.
// Read docs/BEGINNER_GUIDE.md for the app flow and Dart syntax explanations.
// Imported by:
// - lib/features/shell/presentation/main_shell.dart

import 'package:flutter/material.dart';

import '../../../app/app_services.dart';
import '../../../core/utils/date_labels.dart';
import '../../../core/widgets/fit_widgets.dart';
import '../domain/workout_models.dart';
import '../domain/workout_policy.dart';
import 'workout_card.dart';
import 'workout_detail_screen.dart';

/// Workouts tab created in MainShell._pages; opens WorkoutDetailScreen.
class WorkoutsScreen extends StatelessWidget {
  /// Creates WorkoutsScreen; required arguments supply its dependencies or display data.
  const WorkoutsScreen({super.key});

  /// Flutter calls this to describe the UI. context locates services/theme/navigation above this widget.
  @override
  Widget build(BuildContext context) {
    // Shared view model (controller); this screen reads its state and calls its actions.
    final vm = AppServices.of(context).workouts;
    return AnimatedBuilder(
      animation: vm,
      builder: (context, _) {
        if (vm.loadError != null) {
          return Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(
                padding: const EdgeInsets.all(24), child: Text(vm.loadError!)),
            FilledButton(
                onPressed: vm.load, child: const Text("Retry loading")),
          ]));
        }
        if (!vm.isLoaded) {
          return const Center(child: CircularProgressIndicator());
        }
        // Map grouping plans by scheduled calendar date for WorkoutsScreen.
        final days = <String, List<WorkoutPlan>>{};
        for (final workout in vm.workouts) {
          // Calendar-date key used to group these workouts together.
          final key =
              '${workout.scheduledAt.year}-${workout.scheduledAt.month}-${workout.scheduledAt.day}';
          days.putIfAbsent(key, () => []).add(workout);
        }
        return ListView(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 28),
            children: [
              const SectionHeading('Built for progress.',
                  subtitle: 'Follow your workouts, one session at a time.'),
              const SizedBox(height: 20),
              for (final dayWorkouts in days.values) ...[
                Padding(
                  padding: const EdgeInsets.only(top: 16, bottom: 13),
                  child: Text(_dayHeading(dayWorkouts.first.scheduledAt),
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w900)),
                ),
                for (final workout in dayWorkouts) ...[
                  WorkoutCard(
                    workout: workout,
                    vm: vm,
                    onTap: vm.status(workout) == WorkoutAvailability.ready
                        ? () => Navigator.of(context).push(
                            MaterialPageRoute<void>(
                                builder: (_) =>
                                    WorkoutDetailScreen(workout: workout)))
                        : null,
                  ),
                  const SizedBox(height: 12),
                ],
              ],
            ]);
      },
    );
  }

  /// Builds Today/Yesterday/Tomorrow or a full date label; called for each WorkoutsScreen group.
  String _dayHeading(DateTime date) {
    // Current date used for today’s grouping, calendar labels, or relative sample data.
    final today = DateTime.now();
    if (isSameDate(date, today)) return 'Today · ${shortDate(date)}';
    if (isSameDate(date, today.subtract(const Duration(days: 1)))) {
      return 'Yesterday · ${shortDate(date)}';
    }
    if (isSameDate(date, today.add(const Duration(days: 1)))) {
      return 'Tomorrow · ${shortDate(date)}';
    }
    return longDate(date);
  }
}

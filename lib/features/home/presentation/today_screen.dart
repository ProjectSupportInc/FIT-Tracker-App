// Shows a selectable week, today’s progress, and workouts for the selected date.
// Read docs/BEGINNER_GUIDE.md for the app flow and Dart syntax explanations.
// Imported by:
// - lib/features/shell/presentation/main_shell.dart

import 'package:flutter/material.dart';

import '../../../app/app_services.dart';
import '../../../app/fittracker_theme.dart';
import '../../../core/utils/date_labels.dart';
import '../../../core/widgets/fit_widgets.dart';
import '../../workouts/domain/workout_policy.dart';
import '../../workouts/presentation/workout_card.dart';
import '../../workouts/presentation/workout_detail_screen.dart';

/// Today tab created in MainShell._pages; links ready workouts to WorkoutDetailScreen.
class TodayScreen extends StatefulWidget {
  /// Creates TodayScreen; required arguments supply its dependencies or display data.
  const TodayScreen({super.key});

  /// Flutter calls this when inserting the widget; returns the object that holds its mutable state.
  @override
  State<TodayScreen> createState() => _TodayScreenState();
}

/// Mutable state for TodayScreen. Flutter creates it through createState().
class _TodayScreenState extends State<TodayScreen> {
  DateTime _selectedDay = DateTime.now();

  /// Flutter calls this to describe the UI. context locates services/theme/navigation above this widget.
  @override
  Widget build(BuildContext context) {
    // Shared view model (controller); this screen reads its state and calls its actions.
    final vm = AppServices.of(context).workouts;
    // Current user record used to display name/email; may be null before sign-in.
    final user = AppServices.of(context).auth.user;
    // Current date used for today’s grouping, calendar labels, or relative sample data.
    final today = DateTime.now();
    return AnimatedBuilder(
      animation: vm,
      builder: (context, _) {
        // Plans whose scheduled calendar date matches today; used for daily progress totals.
        final todaysWorkouts =
            vm.workouts.where((w) => isSameDate(w.scheduledAt, today)).toList();
        // Plans matching the selected calendar day; used for the visible workout cards.
        final selectedWorkouts = vm.workouts
            .where((w) => isSameDate(w.scheduledAt, _selectedDay))
            .toList();
        // Number of today’s workouts for which all exercises have saved results.
        final done = todaysWorkouts.where(vm.workoutComplete).length;
        return ListView(
            padding: const EdgeInsets.fromLTRB(22, 18, 22, 30),
            children: [
              Text(longDate(today).toUpperCase(),
                  style: const TextStyle(
                      color: FitColors.peach,
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 1.5)),
              const SizedBox(height: 8),
              Text(
                  'Let\'s get stronger,\n${user?.displayName.split(' ').first ?? 'Athlete'}.',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      height: 1.08,
                      letterSpacing: -1)),
              const SizedBox(height: 19),
              _calendar(context, today),
              const SizedBox(height: 22),
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [Color(0xFF103238), Color(0xFF224E48)]),
                  borderRadius: BorderRadius.circular(26),
                ),
                child: Stack(children: [
                  Positioned(
                      right: -10,
                      top: 0,
                      child: Icon(Icons.fitness_center_rounded,
                          size: 112, color: FitColors.lime.withAlpha(40))),
                  const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        FitBadge('TODAY\'S MINDSET',
                            highlight: true, icon: Icons.bolt),
                        SizedBox(height: 23),
                        Text('Every rep is a step\nforward.',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 27,
                                fontWeight: FontWeight.w900,
                                height: 1.1)),
                        SizedBox(height: 11),
                        Text('Show up. Move with purpose. Get stronger.',
                            style: TextStyle(
                                color: Color(0xFFCCDFD8), fontSize: 12)),
                      ]),
                ]),
              ),
              const SizedBox(height: 25),
              const Text('Your daily progress',
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900)),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                    child: StatTile(
                        number: '$done/${todaysWorkouts.length}',
                        label: 'Workouts completed',
                        icon: Icons.emoji_events_outlined)),
                const SizedBox(width: 12),
                Expanded(
                    child: StatTile(
                        number:
                            '${todaysWorkouts.fold<int>(0, (sum, w) => sum + vm.doneCount(w))}',
                        label: 'Exercises completed',
                        icon: Icons.fitness_center)),
              ]),
              const SizedBox(height: 23),
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Text(
                    isSameDate(_selectedDay, today)
                        ? 'Today\'s workouts'
                        : 'Workouts · ${shortDate(_selectedDay)}',
                    style: const TextStyle(
                        fontSize: 17, fontWeight: FontWeight.w900)),
                if (!isSameDate(_selectedDay, today))
                  TextButton(
                    onPressed: () => setState(() => _selectedDay = today),
                    child: const Text('Back to today'),
                  ),
              ]),
              const SizedBox(height: 12),
              if (selectedWorkouts.isEmpty)
                const FitCard(
                    child: Text('No workouts scheduled for this day.')),
              for (final w in selectedWorkouts) ...[
                WorkoutCard(
                  workout: w,
                  vm: vm,
                  onTap: vm.status(w) == WorkoutAvailability.ready
                      ? () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                              builder: (_) => WorkoutDetailScreen(workout: w)))
                      : null,
                ),
                const SizedBox(height: 12),
              ],
            ]);
      },
    );
  }

  /// Builds seven selectable days starting Monday; called by TodayScreen.build().
  Widget _calendar(BuildContext context, DateTime today) {
    // First day of the displayed week; used to generate seven calendar cells.
    final monday =
        DateTime(today.year, today.month, today.day - today.weekday + 1);
    return Row(
        children: List.generate(7, (i) {
      // Calendar date used for comparison or one generated day in the week selector.
      final day = monday.add(Duration(days: i));
      // Whether this calendar cell matches _selectedDay; controls its highlight.
      final selected = isSameDate(day, _selectedDay);
      return Expanded(
          child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: InkWell(
          onTap: () => setState(() => _selectedDay = day),
          borderRadius: BorderRadius.circular(15),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: selected ? FitColors.lime : Theme.of(context).cardColor,
              borderRadius: BorderRadius.circular(15),
            ),
            child: Column(children: [
              Text(shortWeekday(day).substring(0, 1),
                  style: TextStyle(
                      color: selected ? FitColors.ink : null, fontSize: 11)),
              const SizedBox(height: 8),
              Text('${day.day}',
                  style: TextStyle(
                      color: selected ? FitColors.ink : null,
                      fontSize: 16,
                      fontWeight: FontWeight.w900)),
            ]),
          ),
        ),
      ));
    }));
  }
}

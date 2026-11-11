// Shows live reps, pauses/resumes counting, confirms stopping, and saves a completed exercise.
// Read docs/BEGINNER_GUIDE.md for the app flow and Dart syntax explanations.
// Imported by:
// - lib/features/workouts/presentation/exercise_setup_screen.dart

import 'package:flutter/material.dart';

import '../../../app/app_services.dart';
import '../../../app/fittracker_theme.dart';
import '../../../core/widgets/fit_widgets.dart';
import '../domain/workout_models.dart';
import 'exercise_complete_screen.dart';

/// Replaces ExerciseSetupScreen after counting starts; opens ExerciseCompleteScreen after saving.
class LiveExerciseScreen extends StatefulWidget {
  /// Creates LiveExerciseScreen; required arguments supply its dependencies or display data.
  const LiveExerciseScreen(
      {super.key, required this.workout, required this.exercise});

  /// Selected workout supplied by the previous screen.
  final WorkoutPlan workout;

  /// Selected exercise supplied by the previous screen.
  final ExercisePlan exercise;

  /// Flutter calls this when inserting the widget; returns the object that holds its mutable state.
  @override
  State<LiveExerciseScreen> createState() => _LiveExerciseScreenState();
}

/// Mutable state for LiveExerciseScreen. Flutter creates it through createState().
class _LiveExerciseScreenState extends State<LiveExerciseScreen> {
  /// Prevents repeated actions while an asynchronous request or confirmation is in progress.
  bool _busy = false;

  /// Last action failure, displayed beside the controls so a retry is possible.
  String? _error;

  /// All live commands share the same UI guard as finish/stop.
  Future<void> _togglePause() async {
    final vm = AppServices.of(context).workouts;
    if (_busy || vm.isTrackerBusy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await vm.togglePause();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Reconnection checks that the wearable still has this exercise's session.
  /// A recovered paused session requires an explicit Resume button press.
  Future<void> _reconnect() async {
    final vm = AppServices.of(context).workouts;
    if (_busy || vm.isTrackerBusy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await vm.reconnectActiveExercise();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Shows the stop dialog; _stop() awaits true for Stop exercise or false for cancel/dismissal.
  Future<bool> _confirmStop() async {
    // Dialog result: true to stop, false to continue, or null if dismissed.
    final answer = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
              title: const Text('Stop this exercise?'),
              content: const Text(
                  'Your exercise will remain incomplete. You can restart it later.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: const Text('Keep training')),
                FilledButton(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    child: const Text('Stop exercise')),
              ],
            ));
    return answer ?? false;
  }

  /// Handles close, stop, and blocked system-back requests; confirms once, then stops without saving.
  Future<void> _stop() async {
    final vm = AppServices.of(context).workouts;
    if (_busy || vm.isTrackerBusy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (!await _confirmStop() || !mounted) return;
      await vm.stopWithoutSaving();
      // Explicitly pop only after confirmation; successful pops report didPop=true.
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString());
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Unable to stop this exercise. Please try again.')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Handles Finish Exercise; saves via the controller and replaces this route with the completion page.
  Future<void> _finish() async {
    final vm = AppServices.of(context).workouts;
    if (_busy || vm.isTrackerBusy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      // Whether finishExercise() successfully created a completion record.
      final saved = await vm.finishExercise();
      // The user may have left while awaiting storage; do not use a stale context.
      if (!mounted) return;
      if (!saved) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
          builder: (_) => ExerciseCompleteScreen(
              workout: widget.workout, exercise: widget.exercise)));
    } catch (error) {
      if (mounted) {
        setState(() => _error = error.toString());
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Unable to save this exercise. Please try again.')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Flutter calls this to describe the UI. context locates services/theme/navigation above this widget.
  @override
  Widget build(BuildContext context) {
    // Shared view model (controller); this screen reads its state and calls its actions.
    final vm = AppServices.of(context).workouts;
    return PopScope<void>(
      // Block system back until _stop() confirms and stops the tracker.
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        // didPop is true after our explicit Navigator.pop; do not ask again.
        // result is unused because this route returns void.
        if (!didPop) _stop();
      },
      child: AnimatedBuilder(
          animation: vm,
          builder: (context, _) {
            // Latest live repetition count, used for the large number and progress ring.
            final busy = _busy || vm.isTrackerBusy;
            final disconnected = vm.isDisconnected;
            final error = _error ?? vm.trackerError;
            final current = vm.liveReps;
            // Required repetition count from the selected exercise plan.
            final target = widget.exercise.targetReps;
            // Whether the target is reached; enables the Finish button.
            final completed = current >= target;
            // Repetitions beyond the target, clamped to zero for the extra-reps badge.
            final extra = current > target ? current - target : 0;
            return Scaffold(
              appBar: AppBar(
                title: const Text('Live Repetitions'),
                leading: IconButton(
                    onPressed: busy ? null : _stop,
                    icon: const Icon(Icons.close)),
              ),
              // Fill tall screens; allow scrolling when controls need more room.
              body: CustomScrollView(slivers: [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(24, 22, 24, 25),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(widget.exercise.name,
                              textAlign: TextAlign.center,
                              style: Theme.of(context)
                                  .textTheme
                                  .headlineMedium
                                  ?.copyWith(fontWeight: FontWeight.w900)),
                          const SizedBox(height: 8),
                          Center(
                              child: FitBadge(
                                  vm.hasPendingResult
                                      ? 'Ready to save'
                                      : disconnected
                                          ? 'Tracker disconnected'
                                          : vm.isPaused
                                              ? 'Paused'
                                              : completed
                                                  ? 'Target reached · Keep going'
                                                  : 'Counting reps',
                                  highlight: completed && !disconnected,
                                  icon: disconnected
                                      ? Icons.bluetooth_disabled
                                      : vm.isPaused
                                          ? Icons.pause
                                          : Icons.bolt)),
                          const Spacer(),
                          Center(
                              child: SizedBox(
                            height: 250,
                            width: 250,
                            child: Stack(fit: StackFit.expand, children: [
                              CircularProgressIndicator(
                                  value: target > 0
                                      ? (current / target).clamp(0.0, 1.0)
                                      : 0,
                                  color: FitColors.lime,
                                  backgroundColor: Theme.of(context)
                                      .colorScheme
                                      .surfaceContainerHighest,
                                  strokeWidth: 17,
                                  strokeCap: StrokeCap.round),
                              Center(
                                  child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                    Text('$current',
                                        style: const TextStyle(
                                            fontSize: 86,
                                            fontWeight: FontWeight.w900,
                                            height: 1)),
                                    const SizedBox(height: 5),
                                    Text('of $target target reps'),
                                    if (extra > 0) ...[
                                      const SizedBox(height: 12),
                                      FitBadge('+$extra extra reps',
                                          highlight: true),
                                    ],
                                  ])),
                            ]),
                          )),
                          const Spacer(),
                          if (vm.connectedDevice != null)
                            Center(
                                child: Text(
                                    'Connected · ${vm.connectedDevice!.displayName}',
                                    style: TextStyle(
                                        fontSize: 12,
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant))),
                          const SizedBox(height: 18),
                          if (error != null) ...[
                            Semantics(
                                liveRegion: true,
                                child: Text(error,
                                    style: TextStyle(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .error))),
                            const SizedBox(height: 12),
                          ],
                          if (vm.isTrackerBusy) ...[
                            const LinearProgressIndicator(),
                            const SizedBox(height: 12),
                          ],
                          if (disconnected && !vm.hasPendingResult) ...[
                            const Text(
                                'Counting is interrupted. Reconnect to recover the session, or stop without completing.',
                                textAlign: TextAlign.center),
                            const SizedBox(height: 12),
                            OutlinedButton.icon(
                                onPressed: busy ? null : _reconnect,
                                icon: const Icon(Icons.bluetooth_searching),
                                label: const Text('Reconnect tracker')),
                          ] else if (!vm.hasPendingResult)
                            OutlinedButton.icon(
                              onPressed: busy ||
                                      !vm.isRunning ||
                                      !(vm.trackerStatus?.sensorReady ?? false)
                                  ? null
                                  : _togglePause,
                              icon: Icon(
                                  vm.isPaused ? Icons.play_arrow : Icons.pause),
                              label: Text(vm.isPaused
                                  ? 'Resume counting'
                                  : 'Pause counting'),
                            ),
                          const SizedBox(height: 12),
                          AccentButton(
                              vm.hasPendingResult
                                  ? 'Retry saving'
                                  : 'Finish Exercise',
                              icon: Icons.check_circle_outline,
                              onPressed:
                                  vm.canFinish && !busy ? _finish : null),
                          const SizedBox(height: 12),
                          TextButton(
                              onPressed: busy ? null : _stop,
                              child: const Text('Stop without completing')),
                        ]),
                  ),
                )
              ]),
            );
          }),
    );
  }
}

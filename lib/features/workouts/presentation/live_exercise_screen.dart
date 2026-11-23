// Shows live reps, pauses/resumes counting, confirms stopping, and saves a completed exercise.
// Read docs/BEGINNER_GUIDE.md for the app flow and Dart syntax explanations.
// Imported by:
// - lib/features/workouts/presentation/exercise_setup_screen.dart

import 'package:flutter/material.dart';

import '../../../app/app_services.dart';
import '../../../core/widgets/fit_widgets.dart';
import '../domain/workout_models.dart';
import '../../tracker/domain/tracker_status.dart';
import 'exercise_complete_screen.dart';
import 'workout_stage_view.dart';
import 'workout_audio.dart';

/// Replaces ExerciseSetupScreen after START; guides calibration and counting; opens ExerciseCompleteScreen after saving.
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
  WorkoutAudio? _audio;

  /// Last action failure, displayed beside the controls so a retry is possible.
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _audio = AppServices.of(context).audio;
      _audio?.setWorkoutVisible(true);
      final vm = AppServices.of(context).workouts;
      if (vm.isDisconnected && !vm.sessionInvalid && !vm.hasPendingResult) {
        _reconnect();
      }
    });
  }

  @override
  void dispose() {
    _audio?.setWorkoutVisible(false);
    super.dispose();
  }

  Future<void> _keepInterrupted() async {
    final vm = AppServices.of(context).workouts;
    if (_busy || vm.isTrackerBusy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await vm.keepInterruptedResult();
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

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

  /// Reconnection checks the same device and its reported state/count.
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
    final vm = AppServices.of(context).workouts;
    // Dialog result: true to stop, false to continue, or null if dismissed.
    final answer = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
              title: const Text('Stop this exercise?'),
              content: Text(vm.isDisconnected
                  ? 'This discards the phone session only. The tracker may still be counting. Reconnect to stop it, or power it off. Your exercise will remain incomplete.'
                  : 'Your exercise will remain incomplete. You can restart it later.'),
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

  @override
  Widget build(BuildContext context) {
    final vm = AppServices.of(context).workouts;
    final theme = Theme.of(context);
    return PopScope<void>(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _stop();
      },
      child: AnimatedBuilder(
          animation: vm,
          builder: (context, _) {
            final busy = _busy || vm.isTrackerBusy;
            final disconnected = vm.isDisconnected;
            final error = _error ?? vm.trackerError;
            final state = vm.trackerStatus?.state;
            final needsRecovery = disconnected ||
                vm.sessionInvalid ||
                state == TrackerState.error ||
                (state == TrackerState.finished && !vm.canFinish);
            final showFinish = vm.hasPendingResult ||
                (!disconnected &&
                    (state == TrackerState.running ||
                        state == TrackerState.paused ||
                        state == TrackerState.finished));
            return Scaffold(
              appBar: AppBar(
                title: Text(widget.exercise.name),
                actions: [
                  IconButton(
                      tooltip: 'Guidance and calibration help',
                      icon: const Icon(Icons.volume_up_outlined),
                      onPressed: () => showWorkoutHelp(
                          context, AppServices.of(context).audio))
                ],
                leading: IconButton(
                    onPressed: busy ? null : _stop,
                    tooltip: 'Stop workout',
                    icon: const Icon(Icons.close)),
              ),
              body: SafeArea(
                  top: false,
                  child: LayoutBuilder(
                    builder: (context, constraints) => SingleChildScrollView(
                      child: ConstrainedBox(
                        constraints:
                            BoxConstraints(minHeight: constraints.maxHeight),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(24, 16, 24, 20),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              WorkoutStageView(
                                status: vm.trackerStatus,
                                exerciseKind: widget.exercise.kind,
                                interrupted: vm.sessionInvalid,
                                repetitions: vm.liveReps,
                                target: widget.exercise.targetReps,
                                disconnected: disconnected,
                                readyToSave: vm.hasPendingResult,
                                animate: !busy,
                              ),
                              Padding(
                                padding: const EdgeInsets.only(top: 24),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    if (vm.connectedDevice != null) ...[
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Icon(Icons.bluetooth_connected,
                                              size: 18,
                                              color: theme.colorScheme.primary),
                                          const SizedBox(width: 6),
                                          Flexible(
                                              child: Text(
                                                  vm.connectedDevice!
                                                      .displayName,
                                                  style:
                                                      theme.textTheme.bodySmall,
                                                  textAlign: TextAlign.center)),
                                        ],
                                      ),
                                      const SizedBox(height: 16),
                                    ],
                                    if (error != null) ...[
                                      Semantics(
                                          liveRegion: true,
                                          child: Text(error,
                                              style: theme.textTheme.bodyMedium
                                                  ?.copyWith(
                                                      color: theme
                                                          .colorScheme.error))),
                                      const SizedBox(height: 12),
                                    ],
                                    if (vm.isTrackerBusy) ...[
                                      const LinearProgressIndicator(),
                                      const SizedBox(height: 16),
                                    ],
                                    if (needsRecovery &&
                                        !vm.hasPendingResult) ...[
                                      const Text(
                                          'Your last confirmed count is preserved. The tracker pauses after prolonged loss of contact.',
                                          textAlign: TextAlign.center),
                                      const SizedBox(height: 12),
                                      if (!vm.sessionInvalid)
                                        OutlinedButton.icon(
                                            onPressed: busy ? null : _reconnect,
                                            icon: const Icon(
                                                Icons.bluetooth_searching),
                                            label: const Text(
                                                'Reconnect tracker')),
                                      TextButton(
                                          onPressed:
                                              busy ? null : _keepInterrupted,
                                          child: const Text(
                                              'Keep recorded reps and end')),
                                    ] else if (!vm.hasPendingResult &&
                                        state != TrackerState.finished &&
                                        state != TrackerState.error)
                                      OutlinedButton.icon(
                                        onPressed: busy || !vm.canTogglePause
                                            ? null
                                            : _togglePause,
                                        icon: Icon(vm.isPaused
                                            ? Icons.play_arrow
                                            : Icons.pause),
                                        label: Text(vm.isPaused
                                            ? 'Resume workout'
                                            : 'Pause workout'),
                                      ),
                                    if (showFinish) ...[
                                      const SizedBox(height: 12),
                                      AccentButton(
                                          vm.hasPendingResult
                                              ? 'Retry saving'
                                              : 'Finish Exercise',
                                          icon: Icons.check_circle_outline,
                                          onPressed: vm.canFinish && !busy
                                              ? _finish
                                              : null),
                                    ],
                                    const SizedBox(height: 10),
                                    TextButton(
                                        onPressed: busy ? null : _stop,
                                        child: const Text(
                                            'Stop without completing')),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  )),
            );
          }),
    );
  }
}

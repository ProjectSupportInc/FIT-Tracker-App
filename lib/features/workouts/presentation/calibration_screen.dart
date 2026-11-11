// Displays real reference-repetition progress reported by the connected tracker.
// Imported by exercise_setup_screen.dart; no button synthesizes sensor samples.
import 'package:flutter/material.dart';

import '../../../app/app_services.dart';
import '../../../app/fittracker_theme.dart';
import '../../../core/widgets/fit_widgets.dart';
import '../../tracker/domain/tracker_status.dart';
import '../domain/workout_models.dart';

/// Starts calibration on the ESP32 and waits for its saved-profile confirmation.
class CalibrationScreen extends StatefulWidget {
  const CalibrationScreen({super.key, required this.exercise});

  /// Movement selected in setup; calibration belongs to this device/movement pair.
  final ExercisePlan exercise;

  @override
  State<CalibrationScreen> createState() => _CalibrationScreenState();
}

class _CalibrationScreenState extends State<CalibrationScreen> {
  /// A saved old profile must not look like a newly completed calibration.
  bool _started = false;
  bool _busy = false;
  String? _error;

  /// Sends BEGIN_CALIBRATION; progress arrives later through the view model.
  Future<void> _begin() async {
    final vm = AppServices.of(context).workouts;
    if (_busy || vm.isTrackerBusy || vm.isCalibrating) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await vm.beginCalibration(widget.exercise);
      if (mounted) setState(() => _started = true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Refresh can recover the UI if a progress notification was missed.
  Future<void> _refresh() async {
    final vm = AppServices.of(context).workouts;
    if (_busy || vm.isTrackerBusy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await vm.refreshTrackerStatus();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Prevents calibration from continuing after the user leaves this route.
  Future<void> _leave() async {
    final vm = AppServices.of(context).workouts;
    if (_busy || vm.isTrackerBusy) return;
    setState(() => _busy = true);
    try {
      if (vm.isCalibrating) {
        final leave = await showDialog<bool>(
            context: context,
            builder: (dialogContext) => AlertDialog(
                  title: const Text('Cancel calibration?'),
                  content: const Text(
                      'This calibration is not finished. You can start it again from exercise setup.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(dialogContext, false),
                        child: const Text('Keep calibrating')),
                    FilledButton(
                        onPressed: () => Navigator.pop(dialogContext, true),
                        child: const Text('Cancel calibration')),
                  ],
                ));
        if (leave != true || !mounted) return;
      }
      // FINISH also cancels learning; offline cancellation clears phone-side state.
      if (!vm.isCalibrated(widget.exercise) || vm.isCalibrating) {
        await vm.cancelCalibration();
      }
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = AppServices.of(context).workouts;
    return AnimatedBuilder(
        animation: vm,
        builder: (context, _) {
          final status = vm.trackerStatus;
          final active = vm.isCalibrating;
          final busy = _busy || vm.isTrackerBusy;
          final completed = _started &&
              vm.didCompleteCalibration(widget.exercise) &&
              vm.isCalibrated(widget.exercise) &&
              status?.state == TrackerState.ready;
          final target = status?.calibrationTarget ?? 3;
          final samples = _started || active ? status?.calibrationReps ?? 0 : 0;
          final connected = vm.connectedDevice != null;
          final sensorReady = status?.sensorReady ?? false;
          final error = _error ?? vm.trackerError;
          return PopScope<void>(
            canPop: false,
            onPopInvokedWithResult: (didPop, result) {
              if (!didPop) _leave();
            },
            child: Scaffold(
              appBar: AppBar(
                  title: const Text('Calibrate Movement'),
                  leading: IconButton(
                      onPressed: busy ? null : _leave,
                      icon: const Icon(Icons.arrow_back))),
              body: ListView(padding: const EdgeInsets.all(24), children: [
                SectionHeading('Teach your movement.',
                    subtitle: widget.exercise.name),
                const SizedBox(height: 20),
                FitCard(
                    child: Text(completed
                        ? 'Your tracker has saved this movement profile. You can now start your exercise.'
                        : 'Secure the sensor in its exercise position. After you begin, keep still briefly, then perform $target steady repetitions with a short rest between each. Keep the sensor mounting fixed.')),
                const SizedBox(height: 32),
                Center(
                    child: SizedBox(
                        height: 220,
                        width: 220,
                        child: Stack(fit: StackFit.expand, children: [
                          CircularProgressIndicator(
                              value: target > 0
                                  ? (samples / target).clamp(0.0, 1.0)
                                  : 0,
                              strokeWidth: 14,
                              backgroundColor: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHighest,
                              color: FitColors.lime,
                              strokeCap: StrokeCap.round),
                          Center(
                              child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                Text('$samples / $target',
                                    style: const TextStyle(
                                        fontSize: 54,
                                        fontWeight: FontWeight.w900)),
                                const Text('sensor reference reps'),
                              ])),
                        ]))),
                const SizedBox(height: 28),
                Semantics(
                    liveRegion: true,
                    child: Text(
                        completed
                            ? 'Calibration saved'
                            : !connected
                                ? 'Tracker disconnected'
                                : active
                                    ? 'Learning your movement…'
                                    : 'Ready when you are',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.w800))),
                if (error != null) ...[
                  const SizedBox(height: 14),
                  Text(error,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error)),
                ],
                if (!connected) ...[
                  const SizedBox(height: 12),
                  const Text(
                      'Return to exercise setup to reconnect your tracker and restart calibration.'),
                ] else if (!sensorReady) ...[
                  const SizedBox(height: 12),
                  const Text(
                      'The movement sensor is not ready. Check its connection and keep the tracker still.'),
                ],
                const SizedBox(height: 25),
                if (vm.isTrackerBusy) ...[
                  const LinearProgressIndicator(),
                  const SizedBox(height: 16),
                ],
                if (completed)
                  AccentButton('Done',
                      icon: Icons.check, onPressed: busy ? null : _leave)
                else if (!active)
                  AccentButton(
                      _started ? 'Try calibration again' : 'Begin calibration',
                      icon: Icons.sensors,
                      onPressed:
                          busy || !connected || !sensorReady ? null : _begin),
                if (connected && !completed)
                  TextButton(
                      onPressed: busy ? null : _refresh,
                      child: const Text('Check tracker status')),
                const SizedBox(height: 8),
                if (!completed)
                  OutlinedButton(
                      onPressed: busy ? null : _leave,
                      child: Text(
                          active ? 'Cancel calibration' : 'Back to setup')),
              ]),
            ),
          );
        });
  }
}

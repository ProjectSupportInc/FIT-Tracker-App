import 'package:flutter/material.dart';

import '../../../app/app_services.dart';
import '../../../app/fittracker_theme.dart';
import '../../../core/widgets/fit_widgets.dart';
import '../../tracker/domain/tracker_device.dart';
import '../domain/workout_models.dart';
import 'calibration_screen.dart';
import 'live_exercise_screen.dart';

class ExerciseSetupScreen extends StatefulWidget {
  const ExerciseSetupScreen({super.key, required this.workout, required this.exercise});
  final WorkoutPlan workout;
  final ExercisePlan exercise;

  @override
  State<ExerciseSetupScreen> createState() => _ExerciseSetupScreenState();
}

class _ExerciseSetupScreenState extends State<ExerciseSetupScreen> {
  bool _choosing = false;
  bool _busy = false;
  List<TrackerDevice> _devices = [];

  Future<void> _scan() async {
    setState(() { _busy = true; _choosing = true; });
    try {
      final devices = await AppServices.of(context).workouts.scan();
      if (mounted) setState(() => _devices = devices);
    } catch (_) {
      if (mounted) _error('Unable to scan for devices.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _connect(TrackerDevice device) async {
    setState(() => _busy = true);
    try {
      await AppServices.of(context).workouts.connect(device);
      if (mounted) setState(() => _choosing = false);
    } catch (_) {
      if (mounted) _error('Could not connect to ${device.id}.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _error(String message) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message)));

  Future<void> _start() async {
    setState(() => _busy = true);
    try {
      await AppServices.of(context).workouts.startExercise(widget.workout, widget.exercise);
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
        builder: (_) => LiveExerciseScreen(workout: widget.workout, exercise: widget.exercise)));
    } catch (error) {
      if (mounted) _error('Unable to start exercise: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = AppServices.of(context).workouts;
    return AnimatedBuilder(animation: vm, builder: (context, _) {
      final device = vm.connectedDevice;
      final showPicker = device == null || _choosing;
      return Scaffold(
        appBar: AppBar(title: const Text('Exercise Setup')),
        body: ListView(padding: const EdgeInsets.fromLTRB(22, 10, 22, 30), children: [
          const Text('PREPARE YOUR MOVEMENT', style: TextStyle(
              color: FitColors.peach, fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 1.4)),
          const SizedBox(height: 8),
          SectionHeading(widget.exercise.name, subtitle: widget.exercise.coachTip),
          const SizedBox(height: 23),
          FitCard(child: Row(children: [
            const Icon(Icons.track_changes, color: FitColors.lime, size: 33),
            const SizedBox(width: 13),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('TARGET', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800)),
              Text('${widget.exercise.targetReps} repetitions',
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
            ]),
          ])),
          const SizedBox(height: 23),
          if (showPicker) ...[
            const Text('1. Connect Your Device', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            const SizedBox(height: 12),
            if (_busy) const Center(child: Padding(padding: EdgeInsets.all(22), child: CircularProgressIndicator())),
            for (final item in _devices) ...[
              FitCard(
                onTap: _busy ? null : () => _connect(item),
                child: Row(children: [
                  const Icon(Icons.bluetooth, color: FitColors.lime),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(item.id, style: const TextStyle(fontWeight: FontWeight.w900)),
                    Text('${item.batteryPercent}% battery', style: const TextStyle(fontSize: 12)),
                  ])),
                  const Icon(Icons.chevron_right),
                ]),
              ),
              const SizedBox(height: 10),
            ],
            if (!_busy) AccentButton(_devices.isEmpty ? 'Scan for devices' : 'Scan again',
              onPressed: _scan, icon: Icons.bluetooth_searching),
            if (device != null) ...[
              const SizedBox(height: 12),
              TextButton(onPressed: () => setState(() => _choosing = false),
                child: const Text('Keep current device')),
            ],
          ] else ...[
            FitCard(child: Row(children: [
              const Icon(Icons.bluetooth_connected, color: FitColors.lime),
              const SizedBox(width: 13),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Device connected', style: TextStyle(fontWeight: FontWeight.w900)),
                const SizedBox(height: 4),
                Text(device.id, style: const TextStyle(fontSize: 12)),
              ])),
              TextButton(onPressed: _scan, child: const Text('Change')),
            ])),
            const SizedBox(height: 23),
            const Text('2. Calibrate Movement', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
            const SizedBox(height: 12),
            FitCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(vm.isCalibrated(widget.exercise) ? Icons.verified : Icons.info_outline,
                  color: vm.isCalibrated(widget.exercise) ? FitColors.lime : FitColors.peach),
                const SizedBox(width: 10),
                Expanded(child: Text(vm.isCalibrated(widget.exercise)
                    ? 'Calibration saved for this movement' : 'No saved calibration for this movement',
                  style: const TextStyle(fontWeight: FontWeight.w800))),
              ]),
              const SizedBox(height: 12),
              const Text('Calibration is specific to this device and exercise. You can recalibrate at any time.',
                  style: TextStyle(fontSize: 12)),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => CalibrationScreen(exercise: widget.exercise))),
                icon: const Icon(Icons.tune),
                label: Text(vm.isCalibrated(widget.exercise) ? 'Recalibrate' : 'Calibrate now'),
              ),
            ])),
            const SizedBox(height: 25),
            AccentButton('Start Exercise', onPressed: _busy ? null : _start, icon: Icons.play_arrow_rounded),
          ],
        ]),
      );
    });
  }
}

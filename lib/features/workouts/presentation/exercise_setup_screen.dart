// Connects a real tracker, selects its movement profile, and starts a ready exercise.
// Imported by workout_detail_screen.dart and exercise_complete_screen.dart.
import 'package:flutter/material.dart';

import '../../../app/app_services.dart';
import '../../../app/fittracker_theme.dart';
import '../../../core/widgets/fit_widgets.dart';
import '../../tracker/domain/tracker_device.dart';
import '../domain/workout_models.dart';
import 'calibration_screen.dart';
import 'live_exercise_screen.dart';

/// Preparation route opened from workout details or the preceding completion.
class ExerciseSetupScreen extends StatefulWidget {
  const ExerciseSetupScreen(
      {super.key, required this.workout, required this.exercise});

  /// The scheduled workout and specific movement chosen on the previous screen.
  final WorkoutPlan workout;
  final ExercisePlan exercise;

  @override
  State<ExerciseSetupScreen> createState() => _ExerciseSetupScreenState();
}

class _ExerciseSetupScreenState extends State<ExerciseSetupScreen> {
  /// Local actions disable controls until their awaited BLE command completes.
  bool _busy = false;
  bool _choosing = false;
  bool _hasScanned = false;
  List<TrackerDevice> _devices = [];
  String? _lastError;

  @override
  void initState() {
    super.initState();
    // A connection is reusable, but each exercise must select its own profile.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && AppServices.of(context).workouts.connectedDevice != null) {
        _prepare();
      }
    });
  }

  /// Displays actionable BLE errors, including disabled Bluetooth or permissions.
  void _error(Object error) {
    if (!mounted) return;
    setState(() => _lastError = error.toString());
  }

  /// Refreshes the selected movement and reads its persisted calibration status.
  Future<void> _prepare() async {
    final vm = AppServices.of(context).workouts;
    if (_busy || vm.isTrackerBusy) return;
    setState(() {
      _busy = true;
      _lastError = null;
    });
    try {
      await vm.prepareExercise(widget.exercise);
    } catch (error) {
      _error(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Scans for compatible BLE advertisements; it never inserts sample devices.
  Future<void> _scan() async {
    final vm = AppServices.of(context).workouts;
    if (_busy || vm.isTrackerBusy) return;
    setState(() {
      _busy = true;
      _choosing = true;
      _lastError = null;
    });
    try {
      final devices = await vm.scan();
      if (mounted) {
        setState(() {
          _devices = devices;
          _hasScanned = true;
        });
      }
    } catch (error) {
      _error(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// A device is usable only after discovery/subscription and movement selection.
  Future<void> _connect(TrackerDevice device) async {
    final vm = AppServices.of(context).workouts;
    if (_busy || vm.isTrackerBusy) return;
    setState(() {
      _busy = true;
      _lastError = null;
    });
    try {
      await vm.connect(device);
      await vm.prepareExercise(widget.exercise);
      if (mounted) setState(() => _choosing = false);
    } catch (error) {
      _error(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Start waits for the wearable's acknowledgement before opening live counting.
  Future<void> _start() async {
    final vm = AppServices.of(context).workouts;
    if (_busy || vm.isTrackerBusy || !vm.canStartExercise(widget.exercise)) {
      return;
    }
    setState(() {
      _busy = true;
      _lastError = null;
    });
    try {
      await vm.startExercise(widget.workout, widget.exercise);
      if (!mounted) {
        await vm.stopWithoutSaving();
        return;
      }
      Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
        builder: (_) => LiveExerciseScreen(
            workout: widget.workout, exercise: widget.exercise),
      ));
    } catch (error) {
      _error(error);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Calibration reports live reference reps; returning rechecks the profile.
  Future<void> _calibrate() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => CalibrationScreen(exercise: widget.exercise),
    ));
    if (mounted && AppServices.of(context).workouts.connectedDevice != null) {
      await _prepare();
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = AppServices.of(context).workouts;
    return AnimatedBuilder(
        animation: vm,
        builder: (context, _) {
          final device = vm.connectedDevice;
          final busy = _busy || vm.isTrackerBusy;
          final showPicker = device == null || _choosing;
          final calibrated = vm.isCalibrated(widget.exercise);
          final sensorReady = vm.trackerStatus?.sensorReady ?? false;
          final error = _lastError ?? vm.trackerError;
          return PopScope<void>(
            // Avoid leaving while START is in flight and abandoning a running sensor.
            canPop: !busy,
            child: Scaffold(
              appBar: AppBar(title: const Text('Exercise Setup')),
              body: ListView(
                  padding: const EdgeInsets.fromLTRB(22, 10, 22, 30),
                  children: [
                    const Text('PREPARE YOUR MOVEMENT',
                        style: TextStyle(
                            color: FitColors.peach,
                            fontSize: 11,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.4)),
                    const SizedBox(height: 8),
                    SectionHeading(widget.exercise.name,
                        subtitle: widget.exercise.coachTip),
                    const SizedBox(height: 23),
                    FitCard(
                        child: Row(children: [
                      const Icon(Icons.track_changes,
                          color: FitColors.lime, size: 33),
                      const SizedBox(width: 13),
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            const Text('TARGET',
                                style: TextStyle(
                                    fontSize: 11, fontWeight: FontWeight.w800)),
                            Text('${widget.exercise.targetReps} repetitions',
                                style: const TextStyle(
                                    fontSize: 20, fontWeight: FontWeight.w900)),
                          ])),
                    ])),
                    if (error != null) ...[
                      const SizedBox(height: 16),
                      Semantics(
                          liveRegion: true,
                          child: Text(error,
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.error))),
                    ],
                    if (busy) ...[
                      const SizedBox(height: 18),
                      const LinearProgressIndicator(),
                      const SizedBox(height: 8),
                      const Text('Waiting for your tracker…',
                          textAlign: TextAlign.center),
                    ],
                    const SizedBox(height: 23),
                    if (showPicker) ...[
                      const Text('1. Connect Your Device',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 12),
                      const Text(
                          'Turn on your tracker and keep it nearby. Select your device from the scan results.'),
                      const SizedBox(height: 12),
                      if (_hasScanned && _devices.isEmpty && !busy) ...[
                        const FitCard(
                            child: Text(
                                'No compatible trackers found. Check that your tracker is powered on and is not connected to another phone, then scan again.')),
                        const SizedBox(height: 12),
                      ],
                      for (final item in _devices) ...[
                        FitCard(
                            onTap: busy ? null : () => _connect(item),
                            child: Row(children: [
                              const Icon(Icons.bluetooth,
                                  color: FitColors.lime),
                              const SizedBox(width: 12),
                              Expanded(
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                    Text(
                                        item.name.isEmpty
                                            ? 'Fitness tracker'
                                            : item.name,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w900)),
                                    Text(item.id,
                                        style: const TextStyle(fontSize: 12)),
                                    if (item.batteryPercent != null)
                                      Text('${item.batteryPercent}% battery',
                                          style: const TextStyle(fontSize: 12)),
                                  ])),
                              const Icon(Icons.chevron_right),
                            ])),
                        const SizedBox(height: 10),
                      ],
                      AccentButton(
                          _hasScanned ? 'Scan again' : 'Scan for devices',
                          onPressed: busy ? null : _scan,
                          icon: Icons.bluetooth_searching),
                      if (device != null) ...[
                        const SizedBox(height: 12),
                        TextButton(
                            onPressed: busy
                                ? null
                                : () => setState(() => _choosing = false),
                            child: const Text('Keep current device')),
                      ],
                    ] else ...[
                      FitCard(
                          child: Row(children: [
                        const Icon(Icons.bluetooth_connected,
                            color: FitColors.lime),
                        const SizedBox(width: 13),
                        Expanded(
                            child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                              Text(
                                  device.name.isEmpty
                                      ? 'Device connected'
                                      : device.name,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w900)),
                              const SizedBox(height: 4),
                              Text(device.id,
                                  style: const TextStyle(fontSize: 12)),
                            ])),
                        TextButton(
                            onPressed: busy ? null : _scan,
                            child: const Text('Change')),
                      ])),
                      const SizedBox(height: 23),
                      const Text('2. Calibrate Movement',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 12),
                      FitCard(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Row(children: [
                              Icon(
                                  calibrated
                                      ? Icons.verified
                                      : Icons.info_outline,
                                  color: calibrated
                                      ? FitColors.lime
                                      : FitColors.peach),
                              const SizedBox(width: 10),
                              Expanded(
                                  child: Text(
                                      calibrated
                                          ? 'Calibration saved on your tracker'
                                          : 'Calibrate this movement before starting',
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w800))),
                            ]),
                            const SizedBox(height: 12),
                            const Text(
                                'Calibration is specific to this tracker and movement. Recalibrate if you change the sensor placement.',
                                style: TextStyle(fontSize: 12)),
                            if (!sensorReady) ...[
                              const SizedBox(height: 12),
                              const Text(
                                  'The movement sensor is not ready. Check its connection and keep the tracker still, then check again.'),
                            ],
                            const SizedBox(height: 14),
                            OutlinedButton.icon(
                                onPressed:
                                    busy || !sensorReady ? null : _calibrate,
                                icon: const Icon(Icons.tune),
                                label: Text(calibrated
                                    ? 'Recalibrate'
                                    : 'Calibrate now')),
                            TextButton(
                                onPressed: busy ? null : _prepare,
                                child: const Text('Check tracker again')),
                          ])),
                      const SizedBox(height: 25),
                      AccentButton('Start Exercise',
                          onPressed:
                              !busy && vm.canStartExercise(widget.exercise)
                                  ? _start
                                  : null,
                          icon: Icons.play_arrow_rounded),
                      if (!calibrated) ...[
                        const SizedBox(height: 8),
                        const Text(
                            'Start unlocks after the tracker confirms calibration.',
                            textAlign: TextAlign.center),
                      ],
                    ],
                  ]),
            ),
          );
        });
  }
}

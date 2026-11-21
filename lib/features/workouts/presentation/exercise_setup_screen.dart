// Connects a tracker and starts one session that learns and counts the movement.
// Imported by workout_detail_screen.dart and exercise_complete_screen.dart.
import 'package:flutter/material.dart';

import '../../../app/app_services.dart';
import '../../../core/widgets/fit_widgets.dart';
import '../../tracker/domain/tracker_device.dart';
import '../../tracker/domain/tracker_status.dart';
import '../domain/workout_models.dart';
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
  bool _scanning = false;
  bool _hasScanned = false;
  List<TrackerDevice> _devices = [];
  String? _lastError;

  @override
  void initState() {
    super.initState();
    // A connection is reusable; selection is stored only in the phone.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (AppServices.of(context).workouts.connectedDevice != null) {
        _prepare();
      } else {
        _scan();
      }
    });
  }

  /// Displays actionable BLE errors, including disabled Bluetooth or permissions.
  void _error(Object error) {
    if (!mounted) return;
    setState(() => _lastError = error.toString());
  }

  /// Selects the movement locally and reads the current device state.
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
      _scanning = true;
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
      if (mounted) {
        setState(() {
          _busy = false;
          _scanning = false;
        });
      }
    }
  }

  /// Waits for discovery, subscriptions and the current device snapshot.
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

  /// START acknowledgement opens pickup/calibration guidance in the live screen.
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

  @override
  Widget build(BuildContext context) {
    final vm = AppServices.of(context).workouts;
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: vm,
      builder: (context, _) {
        final device = vm.connectedDevice;
        final busy = _busy || vm.isTrackerBusy;
        final showPicker = device == null || _choosing;
        final error = _lastError ?? vm.trackerError;
        return PopScope<void>(
          // Avoid leaving while START is in flight and abandoning a running sensor.
          canPop: !busy,
          child: Scaffold(
            appBar: AppBar(title: const Text('Get ready')),
            body: SafeArea(
              top: false,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(22, 12, 22, 28),
                children: [
                  Text(widget.exercise.name,
                      style: theme.textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  Text('${widget.exercise.targetReps} rep goal',
                      style: theme.textTheme.bodyLarge?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 24),
                  FitCard(
                    padding: const EdgeInsets.all(22),
                    child: AnimatedSwitcher(
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 280),
                      child: showPicker
                          ? _devicePicker(busy, device != null)
                          : _readyToStart(
                              device,
                              busy,
                              vm.canStartExercise(widget.exercise),
                              vm.trackerStatus?.state.isActive == true ||
                                  vm.trackerStatus?.state ==
                                      TrackerState.paused),
                    ),
                  ),
                  if (error != null) ...[
                    const SizedBox(height: 20),
                    Semantics(
                        liveRegion: true,
                        child: Text(error,
                            style: theme.textTheme.bodyMedium
                                ?.copyWith(color: theme.colorScheme.error))),
                  ],
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Connection is the only step shown until a device is ready.
  Widget _devicePicker(bool busy, bool hasConnection) {
    final theme = Theme.of(context);
    return Column(
      key: const ValueKey('device-picker'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _stageIcon(Icons.bluetooth_searching, loading: busy),
        const SizedBox(height: 22),
        Text(_scanning ? 'Finding your tracker…' : 'Connect your tracker',
            textAlign: TextAlign.center, style: theme.textTheme.headlineSmall),
        const SizedBox(height: 10),
        Text(
            _scanning
                ? 'Keep it switched on and nearby.'
                : _devices.isEmpty
                    ? 'Switch on your tracker to get started.'
                    : 'Tap your tracker to connect.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 24),
        if (_hasScanned && _devices.isEmpty && !busy) ...[
          const Text('No compatible trackers found. Move closer and try again.',
              textAlign: TextAlign.center),
          const SizedBox(height: 20),
        ],
        for (final item in _devices) ...[
          OutlinedButton(
            onPressed: busy ? null : () => _connect(item),
            style: OutlinedButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 16)),
            child: Row(children: [
              const Icon(Icons.sensors, size: 28),
              const SizedBox(width: 14),
              Expanded(
                  child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.name.isEmpty ? 'Fitness tracker' : item.name,
                      style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(item.id, style: theme.textTheme.bodySmall),
                  if (item.batteryPercent != null)
                    Text('${item.batteryPercent}% battery',
                        style: theme.textTheme.bodySmall),
                ],
              )),
              const Icon(Icons.chevron_right),
            ]),
          ),
          const SizedBox(height: 12),
        ],
        if (!busy)
          if (_devices.isEmpty)
            AccentButton(_hasScanned ? 'Scan again' : 'Scan for devices',
                onPressed: _scan, icon: Icons.refresh)
          else
            TextButton.icon(
                onPressed: _scan,
                icon: const Icon(Icons.refresh),
                label: const Text('Scan again')),
        if (busy && !_scanning)
          const Text('Connecting…', textAlign: TextAlign.center),
        if (hasConnection)
          TextButton(
              onPressed: busy ? null : () => setState(() => _choosing = false),
              child: const Text('Keep current device')),
      ],
    );
  }

  /// Connection success reveals one primary action, without another checklist.
  Widget _readyToStart(
      TrackerDevice device, bool busy, bool canStart, bool unfinishedSession) {
    final theme = Theme.of(context);
    return Column(
      key: const ValueKey('tracker-ready'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _stageIcon(Icons.check_rounded, loading: busy),
        const SizedBox(height: 22),
        Text(busy ? 'Getting ready…' : 'You’re connected',
            textAlign: TextAlign.center, style: theme.textTheme.headlineSmall),
        const SizedBox(height: 10),
        Text(
            'Secure the sensor to your equipment. We’ll guide you as you move.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 24),
        Row(children: [
          Icon(Icons.bluetooth_connected, color: theme.colorScheme.primary),
          const SizedBox(width: 10),
          Expanded(
              child:
                  Text(device.displayName, style: theme.textTheme.titleMedium)),
          TextButton(
              onPressed: busy ? null : _scan, child: const Text('Change')),
        ]),
        if (unfinishedSession) ...[
          const SizedBox(height: 12),
          const Text(
              'Starting replaces the unfinished session on this tracker.'),
        ],
        const SizedBox(height: 24),
        AccentButton('Start Exercise',
            onPressed: !busy && canStart ? _start : null,
            icon: Icons.play_arrow_rounded),
        if (!busy && !canStart)
          TextButton(
              onPressed: _prepare, child: const Text('Check connection')),
      ],
    );
  }

  Widget _stageIcon(IconData icon, {required bool loading}) {
    final color = Theme.of(context).colorScheme.primary;
    return Center(
        child: SizedBox.square(
      dimension: 96,
      child: Stack(alignment: Alignment.center, children: [
        Container(
            decoration: BoxDecoration(
                shape: BoxShape.circle, color: color.withValues(alpha: 0.1))),
        Icon(icon, size: 44, color: color),
        if (loading)
          const Positioned.fill(
              child: CircularProgressIndicator(strokeWidth: 3)),
      ]),
    ));
  }
}

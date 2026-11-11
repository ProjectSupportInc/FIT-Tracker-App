import 'dart:async';

import '../domain/tracker_device.dart';
import '../domain/tracker_status.dart';
import 'tracker_gateway.dart';

/// Explicit simulation for tests/demo injection only. The running app uses
/// BleTrackerGateway; no failure in real BLE silently falls back to this class.
class MockTrackerGateway implements TrackerGateway {
  final _counts = StreamController<int>.broadcast();
  final _statuses = StreamController<TrackerStatus?>.broadcast();
  final _profiles = <String>{};
  Timer? _timer;
  TrackerDevice? _connected;
  TrackerStatus? _status;

  @override
  Stream<int> get repetitionCounts => _counts.stream;
  @override
  Stream<TrackerStatus?> get statuses => _statuses.stream;
  @override
  TrackerStatus? get status => _status;
  @override
  TrackerDevice? get connectedDevice => _connected;

  @override
  Future<List<TrackerDevice>> scan() async => const [
        TrackerDevice(id: 'demo-01', name: 'Demo tracker', batteryPercent: 92),
      ];

  @override
  Future<void> connect(TrackerDevice device) async {
    _timer?.cancel();
    _connected = device;
    _publish(TrackerState.idle, exerciseId: 0);
  }

  String _key(int id) => '${_connected?.id}:$id';

  void _publish(TrackerState state,
      {int? exerciseId, int? reps, int? calibrationReps}) {
    final id = exerciseId ?? _status?.exerciseId ?? 0;
    _status = TrackerStatus(
      state: state,
      exerciseId: id,
      sensorReady: true,
      profileAvailable: _profiles.contains(_key(id)),
      repetitions: reps ?? _status?.repetitions ?? 0,
      calibrationReps: calibrationReps ?? _status?.calibrationReps ?? 0,
    );
    _statuses.add(_status);
    if (state != TrackerState.calibrating) _counts.add(_status!.repetitions);
  }

  @override
  Future<void> selectExercise({required String exerciseKind}) async {
    if (_connected == null) {
      throw const TrackerException('Connect a tracker first.');
    }
    final id = exerciseIdForKind(exerciseKind);
    _timer?.cancel();
    _publish(
        _profiles.contains(_key(id))
            ? TrackerState.ready
            : TrackerState.selected,
        exerciseId: id,
        reps: 0,
        calibrationReps: 0);
  }

  @override
  Future<void> beginCalibration({required String exerciseKind}) async {
    final id = exerciseIdForKind(exerciseKind);
    if (_connected == null || _status?.exerciseId != id) {
      throw const TrackerException('Select an exercise first.');
    }
    _timer?.cancel();
    _publish(TrackerState.calibrating, calibrationReps: 0);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      final samples = _status!.calibrationReps + 1;
      if (samples == 3) {
        _timer?.cancel();
        _profiles.add(_key(id));
        _publish(TrackerState.ready, calibrationReps: samples);
      } else {
        _publish(TrackerState.calibrating, calibrationReps: samples);
      }
    });
  }

  @override
  Future<void> refreshStatus() async {
    if (_status != null) _statuses.add(_status);
  }

  @override
  Future<void> startCounting({required String exerciseKind}) async {
    final id = exerciseIdForKind(exerciseKind);
    if (_status?.exerciseId != id || !_profiles.contains(_key(id))) {
      throw const TrackerException('Calibrate this movement first.');
    }
    _publish(TrackerState.running, reps: 0);
    _begin();
  }

  void _begin() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 1250), (_) {
      _publish(TrackerState.running, reps: _status!.repetitions + 1);
    });
  }

  @override
  Future<void> pauseCounting() async {
    _timer?.cancel();
    _publish(TrackerState.paused);
  }

  @override
  Future<void> resumeCounting() async {
    _publish(TrackerState.running);
    _begin();
  }

  @override
  Future<void> stopCounting() async {
    _timer?.cancel();
    _publish(_status?.profileAvailable == true
        ? TrackerState.ready
        : TrackerState.selected);
  }

  @override
  Future<void> disconnect() async {
    _timer?.cancel();
    _connected = null;
    _status = null;
    _statuses.add(null);
  }

  @override
  Future<void> dispose() async {
    _timer?.cancel();
    await _counts.close();
    await _statuses.close();
  }
}

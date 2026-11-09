import 'dart:async';

import '../domain/tracker_device.dart';
import 'tracker_gateway.dart';

/// Development adapter: fake devices and monotonically increasing rep events.
class MockTrackerGateway implements TrackerGateway {
  final StreamController<int> _counts = StreamController<int>.broadcast();
  Timer? _timer;
  int _currentReps = 0;
  TrackerDevice? _connected;

  @override
  Stream<int> get repetitionCounts => _counts.stream;
  @override
  TrackerDevice? get connectedDevice => _connected;

  @override
  Future<List<TrackerDevice>> scan() async {
    await Future<void>.delayed(const Duration(milliseconds: 650));
    return const [
      TrackerDevice(id: 'FitTrackerIOT-01', batteryPercent: 92),
      TrackerDevice(id: 'FitTrackerIOT-02', batteryPercent: 78),
      TrackerDevice(id: 'FitTrackerIOT-03', batteryPercent: 64),
    ];
  }

  @override
  Future<void> connect(TrackerDevice device) async {
    await stopCounting();
    await Future<void>.delayed(const Duration(milliseconds: 400));
    _connected = device;
  }

  void _begin() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(milliseconds: 1250), (_) {
      _currentReps++;
      if (!_counts.isClosed) _counts.add(_currentReps);
    });
  }

  @override
  Future<void> startCounting({required String exerciseKind}) async {
    if (_connected == null) throw StateError('No wearable connected');
    _currentReps = 0;
    _begin();
  }

  @override
  Future<void> saveCalibration({required String exerciseKind, required int referenceReps}) async {}

  @override
  Future<void> pauseCounting() async {
    _timer?.cancel();
  }

  @override
  Future<void> resumeCounting() async {
    _begin();
  }

  @override
  Future<void> stopCounting() async {
    _timer?.cancel();
  }

  @override
  Future<void> disconnect() async {
    await stopCounting();
    _connected = null;
  }

  @override
  Future<void> dispose() async {
    await stopCounting();
    await _counts.close();
  }
}

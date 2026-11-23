import 'dart:async';
import '../domain/tracker_device.dart';
import '../domain/tracker_status.dart';
import 'tracker_gateway.dart';

/// Explicit test/demo dependency only. Normal app launches use BleTrackerGateway.
/// Tests publish sensor events themselves; no timer invents workout repetitions.
class MockTrackerGateway implements TrackerGateway {
  final controller = StreamController<int>.broadcast(sync: true);
  final statusController =
      StreamController<TrackerStatus?>.broadcast(sync: true);
  TrackerDevice? device;
  TrackerStatus? _status;
  int bootId = 1;
  int sessionId = 0;
  @override
  void bindSession({required int bootId, required int sessionId}) {}

  TrackerState _beforePause = TrackerState.running;

  @override
  Stream<int> get repetitionCounts => controller.stream;
  @override
  Stream<TrackerStatus?> get statuses => statusController.stream;
  @override
  TrackerStatus? get status => _status;
  @override
  TrackerDevice? get connectedDevice => device;

  void emitStatus(TrackerStatus? value) {
    if (value == null) device = null;
    _status = value;
    statusController.add(value);
  }

  void publish(TrackerState state, {int? reps, int calReps = 0}) =>
      emitStatus(TrackerStatus(
          state: state,
          bootId: bootId,
          sessionId: sessionId,
          repetitions: reps ?? _status?.repetitions ?? 0,
          calibrationReps: calReps));

  void emitReps(int count) {
    publish(_status?.state ?? TrackerState.running, reps: count);
    controller.add(count);
  }

  void completeCalibration() =>
      publish(TrackerState.running, reps: 3, calReps: 3);

  @override
  Future<List<TrackerDevice>> scan() async =>
      const [TrackerDevice(id: 'FT-01', name: 'Test tracker')];
  @override
  Future<void> connect(TrackerDevice next) async {
    device = next;
    emitStatus(_status ?? const TrackerStatus(state: TrackerState.idle));
  }

  @override
  Future<void> disconnect() async => emitStatus(null);
  @override
  Future<void> refreshStatus() async => statusController.add(_status);
  @override
  Future<void> startCounting({int? sessionId}) async {
    this.sessionId = sessionId ?? this.sessionId + 1;
    publish(TrackerState.waitPickup, reps: 0);
  }

  @override
  Future<void> pauseCounting() async {
    _beforePause = _status!.state;
    publish(TrackerState.paused);
  }

  @override
  Future<void> resumeCounting() async => publish(_beforePause.isPreparing
      ? TrackerState.waitPickup
      : TrackerState.running);
  @override
  Future<void> reset() async {
    sessionId = 0;
    publish(TrackerState.idle, reps: 0);
  }

  @override
  Future<void> stopCounting() async => publish(TrackerState.finished);
  @override
  Future<void> dispose() async {
    await controller.close();
    await statusController.close();
  }
}

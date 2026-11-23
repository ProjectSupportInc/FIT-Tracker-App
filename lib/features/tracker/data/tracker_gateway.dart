import '../domain/tracker_device.dart';
import '../domain/tracker_status.dart';

/// Hardware-independent wearable contract used by WorkoutViewModel.
/// BleTrackerGateway is the real implementation; mocks are for explicit tests.
abstract class TrackerGateway {
  Stream<int> get repetitionCounts;

  /// Current device snapshots; null means the BLE connection has been lost/closed.
  Stream<TrackerStatus?> get statuses;
  TrackerStatus? get status;
  TrackerDevice? get connectedDevice;

  Future<List<TrackerDevice>> scan();
  Future<void> connect(TrackerDevice device);
  Future<void> disconnect();

  Future<void> refreshStatus();

  /// START begins pickup, settling, three calibration reps, then counting.
  Future<void> startCounting({int? sessionId});
  void bindSession({required int bootId, required int sessionId});
  Future<void> pauseCounting();
  Future<void> resumeCounting();

  /// Discard a previous session or recover from ERROR before starting again.
  Future<void> reset();

  /// FINISH stops an active session; status contains the firmware's reported total.
  Future<void> stopCounting();
  Future<void> dispose();
}

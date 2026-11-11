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

  /// Ask firmware to select the movement and report whether its profile exists.
  Future<void> selectExercise({required String exerciseKind});

  /// Firmware collects real sensor repetitions and persists the learned profile.
  Future<void> beginCalibration({required String exerciseKind});
  Future<void> refreshStatus();
  Future<void> startCounting({required String exerciseKind});
  Future<void> pauseCounting();
  Future<void> resumeCounting();

  /// FINISH stops counting or cancels calibration; its ACK contains the final count.
  Future<void> stopCounting();
  Future<void> dispose();
}

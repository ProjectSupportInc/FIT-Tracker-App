import '../domain/tracker_device.dart';

/// Platform-independent wearable boundary. Real implementation will use BLE.
abstract class TrackerGateway {
  Stream<int> get repetitionCounts;
  TrackerDevice? get connectedDevice;
  Future<List<TrackerDevice>> scan();
  Future<void> connect(TrackerDevice device);
  Future<void> disconnect();
  Future<void> startCounting({required String exerciseKind});
  Future<void> saveCalibration({required String exerciseKind, required int referenceReps});
  Future<void> pauseCounting();
  Future<void> resumeCounting();
  Future<void> stopCounting();
  Future<void> dispose();
}

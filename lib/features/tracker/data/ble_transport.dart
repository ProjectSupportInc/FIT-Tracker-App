import '../domain/tracker_device.dart';

/// Byte-level transport injected into BleTrackerGateway. Keeping plugin types
/// here makes the packet/command logic testable without a phone or ESP32.
abstract class BleTransport {
  Stream<List<int>> get statusPackets;
  Stream<List<int>> get repetitionPackets;
  Stream<void> get disconnections;
  Future<List<TrackerDevice>> scan();

  /// Completes after service discovery and both notification subscriptions exist.
  Future<void> connect(TrackerDevice device);
  Future<List<int>> readStatus();
  Future<void> writeControl(List<int> packet);
  Future<void> disconnect();
  Future<void> dispose();
}

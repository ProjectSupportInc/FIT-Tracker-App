/// A discovered wearable. [id] is the platform's stable BLE remote identifier;
/// names are only display labels, so two identically named trackers remain distinct.
class TrackerDevice {
  const TrackerDevice(
      {required this.id, this.name = '', this.batteryPercent, this.rssi});

  final String id;
  final String name;

  /// Null when firmware has no battery characteristic; never invent a percentage.
  final int? batteryPercent;

  /// Received signal strength from the scan advertisement, when available.
  final int? rssi;

  String get displayName => name.isEmpty ? 'Fitness tracker' : name;
}

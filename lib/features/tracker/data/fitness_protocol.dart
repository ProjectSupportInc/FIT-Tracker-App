import 'dart:typed_data';
import '../domain/tracker_status.dart';

/// Mirrors app/ft_protocol on feature/port-to-freeRTOS. All packets are eight
/// bytes, little endian. Exercise selection belongs to the phone, not the wire.
class FitnessProtocol {
  static const serviceUuid = '12345678-1234-5678-1234-56789abcdef0';
  static const telemetryUuid = '12345678-1234-5678-1234-56789abcdef1';
  static const controlUuid = '12345678-1234-5678-1234-56789abcdef2';
  static const statusUuid = '12345678-1234-5678-1234-56789abcdef3';
  static const version = 1;

  static List<int> command(TrackerCommand command, int requestId) {
    if (requestId < 1 || requestId > 65535) {
      throw ArgumentError('Request ID must be a nonzero uint16.');
    }
    // ByteData initializes the four reserved bytes to zero.
    final bytes = ByteData(8)
      ..setUint8(0, version)
      ..setUint8(1, command.code)
      ..setUint16(2, requestId, Endian.little);
    return bytes.buffer.asUint8List();
  }

  static TrackerStatus decodeStatus(List<int> bytes) {
    final data = _packet(bytes);
    if (bytes[1] >= TrackerState.values.length ||
        bytes[2] >= TrackerEvent.values.length) {
      throw const FormatException('Unknown tracker state/event.');
    }
    final event = TrackerEvent.values[bytes[2]];
    if ((event == TrackerEvent.calibrationRep &&
            (bytes[3] < 1 || bytes[3] > 3)) ||
        (event == TrackerEvent.commandRejected &&
            (bytes[3] < 1 || bytes[3] > 3))) {
      throw const FormatException('Invalid tracker event detail.');
    }
    return TrackerStatus(
      state: TrackerState.values[bytes[1]],
      event: event,
      detail: bytes[3],
      requestId: data.getUint16(4, Endian.little),
      repetitions: data.getUint16(6, Endian.little),
    );
  }

  static TrackerRepEvent decodeRepetition(List<int> bytes) {
    final data = _packet(bytes);
    if (bytes[1] != 1) {
      throw const FormatException('Unknown telemetry event.');
    }
    return TrackerRepEvent(
        data.getUint16(2, Endian.little), data.getUint32(4, Endian.little));
  }

  static ByteData _packet(List<int> bytes) {
    if (bytes.length != 8 ||
        bytes.any((value) => value < 0 || value > 255) ||
        bytes[0] != version) {
      throw const FormatException('Unsupported or malformed tracker packet.');
    }
    return ByteData.sublistView(Uint8List.fromList(bytes));
  }

  static String resultMessage(int result) => switch (result) {
        1 =>
          'This action is unavailable in the tracker’s current state. Refresh and try again.',
        2 => 'The tracker is busy. Please wait and try again.',
        3 => 'A tracker task failed. Stop the session and restart the tracker.',
        _ => 'The tracker rejected the action.',
      };
}

enum TrackerCommand {
  start(1),
  pause(2),
  resume(3),
  reset(4),
  finish(5),
  getStatus(6);

  const TrackerCommand(this.code);
  final int code;
}

class TrackerRepEvent {
  const TrackerRepEvent(this.repetitions, this.uptimeMs);
  final int repetitions;
  final int uptimeMs;
}

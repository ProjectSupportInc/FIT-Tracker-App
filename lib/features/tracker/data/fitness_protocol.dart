import 'dart:typed_data';

import '../domain/tracker_status.dart';

/// Version-one packet codec mirrored from firmware fitness_protocol.h.
/// All multi-byte fields use little-endian order; no JSON/string BLE guessing.
class FitnessProtocol {
  static const serviceUuid = '12345678-1234-5678-1234-56789abcdef0';
  static const telemetryUuid = '12345678-1234-5678-1234-56789abcdef1';
  static const controlUuid = '12345678-1234-5678-1234-56789abcdef2';
  static const statusUuid = '12345678-1234-5678-1234-56789abcdef3';
  static const version = 1;

  static List<int> command(
      TrackerCommand command, int requestId, int exerciseId) {
    if (requestId < 1 ||
        requestId > 65535 ||
        exerciseId < 0 ||
        exerciseId > 65535) {
      throw ArgumentError(
          'Request/exercise identifier is outside uint16 range.');
    }
    final bytes = ByteData(8)
      ..setUint8(0, version)
      ..setUint8(1, command.code)
      ..setUint16(2, requestId, Endian.little)
      ..setUint16(4, exerciseId, Endian.little);
    return bytes.buffer.asUint8List();
  }

  static TrackerStatus decodeStatus(List<int> bytes) {
    final data = _packet(bytes, 16);
    final state = data.getUint8(1);
    final flags = data.getUint8(2);
    final result = data.getUint8(3);
    if (state >= TrackerState.values.length ||
        flags & ~3 != 0 ||
        result > 7 ||
        data.getUint16(14, Endian.little) != 0 ||
        bytes[12] > bytes[13]) {
      throw const FormatException('Invalid tracker status fields.');
    }
    return TrackerStatus(
      state: TrackerState.values[state],
      exerciseId: data.getUint16(6, Endian.little),
      sensorReady: flags & 2 != 0,
      profileAvailable: flags & 1 != 0,
      repetitions: data.getUint32(8, Endian.little),
      calibrationReps: bytes[12],
      calibrationTarget: bytes[13],
      result: result,
      requestId: data.getUint16(4, Endian.little),
    );
  }

  static TrackerRepEvent decodeRepetition(List<int> bytes) {
    final data = _packet(bytes, 12);
    if (bytes[1] != 1) {
      throw const FormatException('Unknown tracker event type.');
    }
    return TrackerRepEvent(
      data.getUint16(2, Endian.little),
      data.getUint32(4, Endian.little),
      data.getUint32(8, Endian.little),
    );
  }

  static ByteData _packet(List<int> bytes, int length) {
    if (bytes.length != length ||
        bytes.any((value) => value < 0 || value > 255) ||
        bytes[0] != version) {
      throw const FormatException('Unsupported or malformed tracker packet.');
    }
    return ByteData.sublistView(Uint8List.fromList(bytes));
  }

  static String resultMessage(int result) => switch (result) {
        1 => 'The tracker does not support this exercise.',
        2 =>
          'The tracker is in a different state. Refresh or reconnect and try again.',
        3 => 'Calibrate this movement before starting.',
        4 => 'The tracker could not save its calibration. Please retry.',
        5 =>
          'The motion sensor is not ready. Check the sensor and keep it still.',
        6 => 'The tracker firmware does not support this command.',
        7 => 'The tracker is busy. Please wait and try again.',
        _ => 'The tracker reported an error.',
      };
}

/// Explicit wire opcodes, rather than relying on Dart enum indexes.
enum TrackerCommand {
  select(1),
  calibrate(2),
  start(3),
  pause(4),
  finish(5),
  getStatus(6);

  const TrackerCommand(this.code);
  final int code;
}

class TrackerRepEvent {
  const TrackerRepEvent(this.exerciseId, this.repetitions, this.uptimeMs);
  final int exerciseId;
  final int repetitions;
  final int uptimeMs;
}

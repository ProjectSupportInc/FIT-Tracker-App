import 'package:flutter_test/flutter_test.dart';
import 'package:repform_app/features/tracker/data/fitness_protocol.dart';
import 'package:repform_app/features/tracker/domain/tracker_status.dart';

void main() {
  test('All six commands use firmware opcodes and zero reserved bytes', () {
    for (var i = 0; i < TrackerCommand.values.length; i++) {
      expect(FitnessProtocol.command(TrackerCommand.values[i], 0x1234),
          [1, i + 1, 0x34, 0x12, 0, 0, 0, 0]);
    }
    expect(() => FitnessProtocol.command(TrackerCommand.start, 0),
        throwsArgumentError);
    expect(() => FitnessProtocol.command(TrackerCommand.start, 65536),
        throwsArgumentError);
  });
  test('Eight-byte status matches firmware field offsets', () {
    final status =
        FitnessProtocol.decodeStatus([1, 4, 7, 0, 0x34, 0x12, 0x78, 0x56]);
    expect(status.state, TrackerState.running);
    expect(status.event, TrackerEvent.templateLocked);
    expect(status.requestId, 0x1234);
    expect(status.repetitions, 0x5678);
    final rejected = FitnessProtocol.decodeStatus([1, 5, 2, 2, 1, 0, 3, 0]);
    expect(rejected.event, TrackerEvent.commandRejected);
    expect(rejected.detail, 2);
  });
  test('Telemetry has a uint16 total and uint32 uptime, with no exercise ID',
      () {
    final event = FitnessProtocol.decodeRepetition(
        [1, 1, 0xff, 0xff, 0x78, 0x56, 0x34, 0x12]);
    expect(event.repetitions, 65535);
    expect(event.uptimeMs, 0x12345678);
  });
  test('Old protocol, malformed fields, versions and lengths are rejected', () {
    for (final bytes in <List<int>>[
      [],
      [1, 0],
      [1, ...List.filled(15, 0)],
      [2, 0, 0, 0, 0, 0, 0, 0],
      [1, 8, 0, 0, 0, 0, 0, 0],
      [1, 0, 9, 0, 0, 0, 0, 0],
      [1, 3, 5, 4, 0, 0, 0, 0],
      [1, 0, 2, 0, 0, 0, 0, 0],
      [1, 0, 0, 0, 0, 0, -1, 0],
    ]) {
      expect(() => FitnessProtocol.decodeStatus(bytes), throwsFormatException);
    }
    expect(() => FitnessProtocol.decodeRepetition([1, ...List.filled(11, 0)]),
        throwsFormatException);
    expect(() => FitnessProtocol.decodeRepetition([1, 2, 0, 0, 0, 0, 0, 0]),
        throwsFormatException);
  });
}

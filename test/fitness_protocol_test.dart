import 'package:flutter_test/flutter_test.dart';
import 'package:repform_app/features/tracker/data/fitness_protocol.dart';
import 'package:repform_app/features/tracker/domain/tracker_status.dart';

void main() {
  test('Version 2 commands carry expected boot and session identities', () {
    for (var i = 0; i < TrackerCommand.values.length; i++) {
      expect(
          FitnessProtocol.command(TrackerCommand.values[i], 0x1234,
              bootId: 0x12345678, sessionId: 0x90abcdef),
          [
            2,
            i + 1,
            0x34,
            0x12,
            0x78,
            0x56,
            0x34,
            0x12,
            0xef,
            0xcd,
            0xab,
            0x90
          ]);
    }
    expect(() => FitnessProtocol.command(TrackerCommand.start, 0),
        throwsArgumentError);
    expect(() => FitnessProtocol.command(TrackerCommand.start, 65536),
        throwsArgumentError);
    expect(
        () => FitnessProtocol.command(TrackerCommand.start, 1, sessionId: -1),
        throwsArgumentError);
  });
  const snapshot = [
    2,
    4,
    7,
    0,
    0x34,
    0x12,
    0x78,
    0x56,
    0x78,
    0x56,
    0x34,
    0x12,
    0xef,
    0xcd,
    0xab,
    0x90,
    0x34,
    0x12,
    3,
    2
  ];
  test('Complete twenty-byte snapshot has matching firmware offsets', () {
    final status = FitnessProtocol.decodeStatus(snapshot);
    expect(status.state, TrackerState.running);
    expect(status.event, TrackerEvent.templateLocked);
    expect(status.requestId, 0x1234);
    expect(status.repetitions, 0x5678);
    expect(status.bootId, 0x12345678);
    expect(status.sessionId, 0x90abcdef);
    expect(status.revision, 0x1234);
    expect(status.calibrationReps, 3);
    expect(status.linkPaused, isTrue);
    expect(status.commandPending, isFalse);
  });
  test(
      'Telemetry identifies its session and revision as well as cumulative reps',
      () {
    final event = FitnessProtocol.decodeRepetition([
      2,
      1,
      0xff,
      0xff,
      0x78,
      0x56,
      0x34,
      0x12,
      1,
      0,
      0,
      0,
      2,
      0,
      0,
      0,
      0xff,
      0xff
    ]);
    expect(event.repetitions, 65535);
    expect(event.uptimeMs, 0x12345678);
    expect(event.bootId, 1);
    expect(event.sessionId, 2);
    expect(event.revision, 65535);
  });
  test('Legacy layouts, unknown fields and malformed lengths are rejected', () {
    for (final bytes in <List<int>>[
      [],
      [2, 0],
      [1, ...List.filled(7, 0)],
      [1, ...List.filled(15, 0)],
      [...snapshot]..[0] = 1,
      [...snapshot]..[1] = 8,
      [...snapshot]..[2] = 9,
      [...snapshot]..[18] = 4,
      [...snapshot]..[19] = 4,
      [...snapshot]..[6] = -1,
      [...snapshot]..setRange(8, 12, [0, 0, 0, 0]),
    ]) {
      expect(() => FitnessProtocol.decodeStatus(bytes), throwsFormatException);
    }
    expect(() => FitnessProtocol.decodeRepetition([1, ...List.filled(7, 0)]),
        throwsFormatException);
  });
}

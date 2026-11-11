import 'package:flutter_test/flutter_test.dart';
import 'package:repform_app/features/tracker/data/fitness_protocol.dart';
import 'package:repform_app/features/tracker/domain/tracker_status.dart';

void main() {
  test('Control packet matches firmware byte order and reserved fields', () {
    expect(FitnessProtocol.command(TrackerCommand.start, 0x1234, 0x5678),
        [1, 3, 0x34, 0x12, 0x78, 0x56, 0, 0]);
    expect(() => FitnessProtocol.command(TrackerCommand.start, 0, 1),
        throwsArgumentError);
  });

  test('Status packet decodes firmware values without clipping overflow reps',
      () {
    final status = FitnessProtocol.decodeStatus([
      1,
      4,
      3,
      0,
      0x34,
      0x12,
      2,
      0,
      0x78,
      0x56,
      0x34,
      0x12,
      3,
      3,
      0,
      0,
    ]);
    expect(status.state, TrackerState.running);
    expect(status.requestId, 0x1234);
    expect(status.exerciseId, 2);
    expect(status.repetitions, 0x12345678);
    expect(status.sensorReady, isTrue);
    expect(status.profileAvailable, isTrue);
    expect(status.calibrationReps, 3);
  });

  test('Telemetry packet decodes cumulative count and uptime', () {
    final event = FitnessProtocol.decodeRepetition(
        [1, 1, 3, 0, 9, 0, 0, 0, 0xff, 0xff, 0, 0]);
    expect(event.exerciseId, 3);
    expect(event.repetitions, 9);
    expect(event.uptimeMs, 65535);
  });

  test(
      'Malformed/unsupported packets are rejected instead of becoming fake counts',
      () {
    final valid = [1, 3, 3, 0, 1, 0, 1, 0, 0, 0, 0, 0, 3, 3, 0, 0];
    for (final invalid in [
      <int>[],
      valid.sublist(1),
      [...valid, 0],
      [...valid]..[0] = 2,
      [...valid]..[1] = 7,
      [...valid]..[2] = 4,
      [...valid]..[3] = 8,
      [...valid]..[12] = 4,
      [...valid]..[15] = 1,
      [...valid]..[5] = 256,
    ]) {
      expect(
          () => FitnessProtocol.decodeStatus(invalid), throwsFormatException);
    }
    expect(
        () => FitnessProtocol.decodeRepetition(
            [1, 2, 1, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
        throwsFormatException);
  });

  test(
      'Movement IDs preserve firmware curl/bench IDs and cover every demo movement',
      () {
    expect(exerciseIdForKind('dumbbell curl'), 1);
    expect(exerciseIdForKind('bench press'), 2);
    expect(exerciseIdForKind('push-ups'), 3);
    expect(exerciseIdForKind('shoulder press'), 4);
    expect(exerciseIdForKind('dumbbell row'), 5);
    expect(exerciseIdForKind('squat'), 6);
    expect(
        () => exerciseIdForKind('unknown'), throwsA(isA<TrackerException>()));
  });
}

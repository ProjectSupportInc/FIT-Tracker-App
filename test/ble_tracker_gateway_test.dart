import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:repform_app/features/tracker/data/ble_tracker_gateway.dart';
import 'package:repform_app/features/tracker/data/ble_transport.dart';
import 'package:repform_app/features/tracker/domain/tracker_device.dart';
import 'package:repform_app/features/tracker/domain/tracker_status.dart';

/// These bytes deliberately come from a tiny fake peripheral, not the app codec.
List<int> _status(
    {int state = 0,
    int flags = 2,
    int result = 0,
    int request = 0,
    int exercise = 0,
    int reps = 0,
    int samples = 0}) {
  final bytes = ByteData(16)
    ..setUint8(0, 1)
    ..setUint8(1, state)
    ..setUint8(2, flags)
    ..setUint8(3, result)
    ..setUint16(4, request, Endian.little)
    ..setUint16(6, exercise, Endian.little)
    ..setUint32(8, reps, Endian.little)
    ..setUint8(12, samples)
    ..setUint8(13, 3);
  return bytes.buffer.asUint8List();
}

class _Peripheral implements BleTransport {
  final statusController = StreamController<List<int>>.broadcast(sync: true);
  final repController = StreamController<List<int>>.broadcast(sync: true);
  final disconnectController = StreamController<void>.broadcast(sync: true);
  final writes = <List<int>>[];
  Future<void> Function(List<int>)? onWrite;
  int disconnectCalls = 0;
  List<int> snapshot = _status();

  @override
  Stream<List<int>> get statusPackets => statusController.stream;
  @override
  Stream<List<int>> get repetitionPackets => repController.stream;
  @override
  Stream<void> get disconnections => disconnectController.stream;
  @override
  Future<List<TrackerDevice>> scan() async =>
      const [TrackerDevice(id: 'esp32', name: 'FitnessTracker')];
  @override
  Future<void> connect(TrackerDevice device) async {}
  @override
  Future<List<int>> readStatus() async => snapshot;
  @override
  Future<void> writeControl(List<int> packet) async {
    writes.add(List.of(packet));
    if (onWrite != null) {
      await onWrite!(packet);
      return;
    }
    final response = List<int>.of(snapshot);
    response[4] = packet[2];
    response[5] = packet[3];
    statusController.add(response);
  }

  @override
  Future<void> disconnect() async {
    disconnectCalls++;
  }

  @override
  Future<void> dispose() async {
    await statusController.close();
    await repController.close();
    await disconnectController.close();
  }

  int request(List<int> packet) => packet[2] | packet[3] << 8;
  int exercise(List<int> packet) => packet[4] | packet[5] << 8;
  void reply(List<int> packet,
      {int state = 3, int flags = 3, int result = 0, int reps = 0}) {
    snapshot = _status(
        state: state,
        flags: flags,
        result: result,
        request: request(packet),
        exercise: exercise(packet),
        reps: reps);
    statusController.add(snapshot);
  }

  void rep(int exercise, int count) => repController.add([
        1,
        1,
        exercise,
        0,
        count & 255,
        count >> 8 & 255,
        count >> 16 & 255,
        count >> 24 & 255,
        1,
        0,
        0,
        0,
      ]);
}

void main() {
  late _Peripheral peripheral;
  late BleTrackerGateway gateway;
  setUp(() async {
    peripheral = _Peripheral();
    gateway = BleTrackerGateway(
        transport: peripheral,
        commandTimeout: const Duration(milliseconds: 100));
    await gateway.connect(const TrackerDevice(id: 'esp32'));
    addTearDown(gateway.dispose);
  });

  test(
      'Connection reads current status then requests a fresh acknowledged status',
      () {
    expect(gateway.connectedDevice!.id, 'esp32');
    expect(gateway.status!.state, TrackerState.idle);
    expect(peripheral.writes.single, [1, 6, 1, 0, 0, 0, 0, 0]);
  });

  test(
      'Only matching request IDs acknowledge an action; unsolicited progress does not',
      () async {
    final written = Completer<List<int>>();
    peripheral.onWrite = (bytes) async {
      written.complete(bytes);
    };
    var completed = false;
    final selection = gateway
        .selectExercise(exerciseKind: 'curl')
        .then((_) => completed = true);
    final command = await written.future;
    peripheral.statusController
        .add(_status(state: 3, flags: 3, exercise: 1, request: 65000));
    peripheral.statusController.add(_status(state: 1, exercise: 1));
    await Future<void>.delayed(Duration.zero);
    expect(completed, isFalse);
    expect(gateway.status!.state, TrackerState.selected);
    peripheral.reply(command);
    await selection;
    expect(gateway.status!.profileAvailable, isTrue);
  });

  test(
      'Firmware rejection reaches the caller and does not claim calibration exists',
      () async {
    peripheral.onWrite = (bytes) async {
      peripheral.reply(bytes, state: 1, flags: 2, result: 3);
    };
    await expectLater(gateway.selectExercise(exerciseKind: 'curl'),
        throwsA(isA<TrackerException>()));
    expect(gateway.status!.profileAvailable, isFalse);
    expect(gateway.connectedDevice, isNotNull);
  });

  test(
      'Calibration progress and saved profile are firmware status, not workout reps',
      () async {
    peripheral.onWrite = (bytes) async {
      peripheral.reply(bytes, state: bytes[1] == 2 ? 2 : 1, flags: 2);
    };
    await gateway.selectExercise(exerciseKind: 'curl');
    await gateway.beginCalibration(exerciseKind: 'curl');
    final counts = <int>[];
    final subscription = gateway.repetitionCounts.listen(counts.add);
    addTearDown(subscription.cancel);
    peripheral.statusController.add(_status(state: 2, exercise: 1, samples: 2));
    peripheral.rep(1, 2);
    await Future<void>.delayed(Duration.zero);
    expect(gateway.status!.calibrationReps, 2);
    expect(counts, isEmpty);
    peripheral.statusController
        .add(_status(state: 3, flags: 3, exercise: 1, samples: 3));
    expect(gateway.status!.state, TrackerState.ready);
    expect(gateway.status!.profileAvailable, isTrue);
  });

  test(
      'Commands serialize, pause/resume preserve reps, FINISH reports final total',
      () async {
    peripheral.onWrite = (bytes) async {
      peripheral.reply(bytes);
    };
    await gateway.selectExercise(exerciseKind: 'curl');
    final started = Completer<List<int>>();
    peripheral.onWrite = (bytes) async {
      if (bytes[1] == 3) {
        started.complete(bytes);
      } else {
        peripheral.reply(bytes, state: 5, reps: 8);
      }
    };
    final start = gateway.startCounting(exerciseKind: 'curl');
    final pause = gateway.pauseCounting();
    final startPacket = await started.future;
    expect(peripheral.writes.last[1], 3);
    peripheral.reply(startPacket, state: 4);
    await start;
    await pause;
    expect(peripheral.writes.last[1], 4);
    expect(gateway.status!.repetitions, 8);
    peripheral.onWrite = (bytes) async {
      peripheral.reply(bytes, state: bytes[1] == 3 ? 4 : 3, reps: 9);
    };
    await gateway.resumeCounting();
    expect(peripheral.writes.last[1], 3);
    await gateway.stopCounting();
    expect(peripheral.writes.last[1], 5);
    expect(gateway.status!.repetitions, 9);
  });

  test('Telemetry accepts only selected exercise and ignores decreasing totals',
      () async {
    peripheral.onWrite = (bytes) async {
      peripheral.reply(bytes, state: bytes[1] == 3 ? 4 : 3);
    };
    await gateway.selectExercise(exerciseKind: 'curl');
    await gateway.startCounting(exerciseKind: 'curl');
    final counts = <int>[];
    final subscription = gateway.repetitionCounts.listen(counts.add);
    addTearDown(subscription.cancel);
    peripheral.rep(1, 8);
    peripheral.rep(2, 55);
    peripheral.rep(1, 3);
    peripheral.rep(1, 9);
    await Future<void>.delayed(Duration.zero);
    expect(counts, [8, 9]);
  });

  test(
      'Disconnect fails pending and queued actions, clears stale device/status',
      () async {
    final written = Completer<void>();
    peripheral.onWrite = (_) async {
      written.complete();
    };
    final selection = gateway.selectExercise(exerciseKind: 'curl');
    final refresh = gateway.refreshStatus();
    final selectionError =
        expectLater(selection, throwsA(isA<TrackerException>()));
    final refreshError = expectLater(refresh, throwsA(isA<TrackerException>()));
    await written.future;
    peripheral.disconnectController.add(null);
    await selectionError;
    await refreshError;
    expect(gateway.connectedDevice, isNull);
    expect(gateway.status, isNull);
    expect(peripheral.writes.length, 2);
  });

  test('Missing ACK times out and disconnects without retrying the command',
      () async {
    peripheral.onWrite = (_) async {};
    final before = peripheral.disconnectCalls;
    await expectLater(gateway.selectExercise(exerciseKind: 'curl'),
        throwsA(isA<TrackerException>()));
    expect(peripheral.disconnectCalls, greaterThan(before));
    expect(peripheral.writes.length, 2);
    expect(gateway.connectedDevice, isNull);
  });

  test('Malformed notification terminates the uncertain BLE session', () async {
    peripheral.statusController.add([1, 2]);
    await Future<void>.delayed(Duration.zero);
    expect(gateway.connectedDevice, isNull);
    expect(gateway.status, isNull);
  });

  test(
      'A queried sensor fault stays visible without breaking the BLE connection',
      () async {
    peripheral.onWrite = (bytes) async {
      peripheral.reply(bytes, state: 5, flags: 1, result: 5, reps: 4);
    };
    await gateway.refreshStatus();
    expect(gateway.connectedDevice, isNotNull);
    expect(gateway.status!.result, 5);
    expect(gateway.status!.sensorReady, isFalse);
  });
}

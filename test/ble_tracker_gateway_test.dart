import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:repform_app/features/tracker/data/ble_tracker_gateway.dart';
import 'package:repform_app/features/tracker/data/ble_transport.dart';
import 'package:repform_app/features/tracker/domain/tracker_device.dart';
import 'package:repform_app/features/tracker/domain/tracker_status.dart';

// Independent peripheral byte fixtures: do not encode responses with the app codec.
List<int> _status(
    {int state = 0,
    int event = 0,
    int detail = 0,
    int request = 0,
    int reps = 0}) {
  final bytes = ByteData(8)
    ..setUint8(0, 1)
    ..setUint8(1, state)
    ..setUint8(2, event)
    ..setUint8(3, detail)
    ..setUint16(4, request, Endian.little)
    ..setUint16(6, reps, Endian.little);
  return bytes.buffer.asUint8List();
}

class _Peripheral implements BleTransport {
  final statusController = StreamController<List<int>>.broadcast(sync: true);
  final repController = StreamController<List<int>>.broadcast(sync: true);
  final disconnectController = StreamController<void>.broadcast(sync: true);
  final writes = <List<int>>[];
  Future<void> Function(List<int>)? onWrite;
  List<int> snapshot = _status();
  int disconnectCalls = 0;
  @override
  Stream<List<int>> get statusPackets => statusController.stream;
  @override
  Stream<List<int>> get repetitionPackets => repController.stream;
  @override
  Stream<void> get disconnections => disconnectController.stream;
  @override
  Future<List<TrackerDevice>> scan() async =>
      const [TrackerDevice(id: 'esp32')];
  @override
  Future<void> connect(TrackerDevice device) async {}
  @override
  Future<List<int>> readStatus() async => snapshot;
  @override
  Future<void> writeControl(List<int> packet) async {
    writes.add(List.of(packet));
    if (onWrite != null) return onWrite!(packet);
    final state = switch (packet[1]) {
      1 => 1,
      2 => 5,
      3 => 4,
      4 => 0,
      5 => 6,
      _ => snapshot[1],
    };
    reply(packet,
        state: state,
        reps: packet[1] == 1 || packet[1] == 4
            ? 0
            : snapshot[6] | snapshot[7] << 8);
  }

  int request(List<int> packet) => packet[2] | packet[3] << 8;
  void reply(List<int> packet,
      {int state = 1,
      int reps = 0,
      int? event,
      int detail = 0,
      int? requestId}) {
    snapshot = _status(
        state: state,
        reps: reps,
        event: event ?? (packet[1] == 6 ? 0 : 1),
        detail: detail,
        request: requestId ?? request(packet));
    statusController.add(snapshot);
  }

  void publish({int state = 0, int event = 0, int detail = 0, int reps = 0}) {
    snapshot = _status(state: state, event: event, detail: detail, reps: reps);
    statusController.add(snapshot);
  }

  void rep(int count) => repController
      .add([1, 1, count & 255, count >> 8, 0x78, 0x56, 0x34, 0x12]);
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

  test('Connect reads status and sends GET_STATUS, no exercise selection', () {
    expect(gateway.status!.state, TrackerState.idle);
    expect(peripheral.writes.single, [1, 6, 1, 0, 0, 0, 0, 0]);
  });
  test('START, PAUSE, RESUME, FINISH and RESET use distinct new opcodes',
      () async {
    await gateway.startCounting();
    expect(gateway.status!.state, TrackerState.waitPickup);
    peripheral.publish(state: 4, event: 7, reps: 3);
    await gateway.pauseCounting();
    await gateway.resumeCounting();
    await gateway.stopCounting();
    expect(gateway.status!.state, TrackerState.finished);
    await gateway.reset();
    expect(gateway.status!.repetitions, 0);
    expect(peripheral.writes.map((p) => p[1]), [6, 1, 2, 3, 6, 5, 4]);
    expect(
        peripheral.writes.every((p) => p.skip(4).every((v) => v == 0)), isTrue);
    expect(peripheral.writes.map(peripheral.request).toSet().length,
        peripheral.writes.length);
  });
  test('Only matching request ID and reply event acknowledge commands',
      () async {
    final written = Completer<List<int>>();
    peripheral.onWrite = (p) async {
      written.complete(p);
    };
    var done = false;
    final start = gateway.startCounting().then((_) => done = true);
    final packet = await written.future;
    peripheral.publish(state: 1); // unsolicited heartbeat
    peripheral.statusController
        .add(_status(state: 1, event: 1, request: 65000));
    peripheral.statusController
        .add(_status(state: 1, request: peripheral.request(packet)));
    await Future<void>.delayed(Duration.zero);
    expect(done, isFalse);
    peripheral.reply(packet);
    await start;
    expect(done, isTrue);
  });
  test(
      'Current firmware wrong ACK request ID is reported, never silently accepted',
      () async {
    peripheral.onWrite = (p) async {
      peripheral.reply(p, requestId: p[1]);
    };
    await expectLater(
        gateway.startCounting(),
        throwsA(isA<TrackerException>()
            .having((e) => e.message, 'message', contains('command number'))));
    expect(gateway.connectedDevice, isNull);
  });
  test('Wrong-event reply with the correct request ID still times out',
      () async {
    peripheral.onWrite = (p) async {
      peripheral.reply(p, event: 0);
    };
    await expectLater(
        gateway.startCounting(), throwsA(isA<TrackerException>()));
    expect(gateway.connectedDevice, isNull);
  });
  test('Rejection detail is a result code, not a calibration count', () async {
    peripheral.onWrite = (p) async {
      peripheral.reply(p, state: 0, event: 2, detail: 2);
    };
    await expectLater(
        gateway.startCounting(),
        throwsA(isA<TrackerException>()
            .having((e) => e.message, 'message', contains('busy'))));
    expect(gateway.connectedDevice, isNotNull);
  });
  test(
      'Calibration events survive heartbeats; reset clears them; template adds three reps',
      () async {
    await gateway.startCounting();
    peripheral.publish(state: 2, event: 3);
    peripheral.publish(state: 3, event: 4);
    peripheral.publish(state: 3, event: 5, detail: 1);
    peripheral.publish(state: 3);
    expect(gateway.status!.calibrationReps, 1);
    peripheral.publish(state: 3, event: 5, detail: 2);
    expect(gateway.status!.calibrationReps, 2);
    peripheral.publish(state: 2, event: 6);
    expect(gateway.status!.calibrationReps, 0);
    peripheral.publish(state: 3, event: 4);
    peripheral.publish(state: 4, event: 7, reps: 3);
    expect(gateway.status!.calibrationReps, 3);
    expect(gateway.status!.repetitions, 3);
    peripheral.publish(state: 4, reps: 4);
    expect(gateway.status!.calibrationReps, 3);
  });
  test('Known firmware CAL_RESET detail=2 is not invented as a successful rep',
      () {
    peripheral.publish(state: 3, event: 5, detail: 1);
    peripheral.publish(state: 3, event: 6, detail: 2);
    expect(gateway.status!.calibrationReps, 0);
    expect(gateway.connectedDevice, isNotNull);
  });
  test(
      'Telemetry cannot count before template lock and ignores decreasing totals',
      () async {
    await gateway.startCounting();
    peripheral.rep(5);
    expect(gateway.status!.repetitions, 0);
    peripheral.publish(state: 4, event: 7, reps: 3);
    peripheral.rep(8);
    expect(gateway.status!.repetitions, 8);
    peripheral.rep(7);
    expect(gateway.status!.repetitions, 8);
  });
  test('FINISH retry queries a finished device without sending another FINISH',
      () async {
    peripheral.publish(state: 6, reps: 12);
    await gateway.stopCounting();
    expect(gateway.status!.repetitions, 12);
    expect(peripheral.writes.map((p) => p[1]), [6, 6]);
  });
  test('A rebooted idle device is not claimed to have finished', () async {
    peripheral.publish(state: 0);
    await gateway.stopCounting();
    expect(gateway.status!.state, TrackerState.idle);
    expect(peripheral.writes.map((p) => p[1]), [6, 6]);
  });
  test(
      'Disconnect fails pending and queued commands without sending them to a new link',
      () async {
    final written = Completer<void>();
    peripheral.onWrite = (_) async {
      written.complete();
    };
    final start = gateway.startCounting();
    final pause = gateway.pauseCounting();
    final checkStart = expectLater(start, throwsA(isA<TrackerException>()));
    final checkPause = expectLater(pause, throwsA(isA<TrackerException>()));
    await written.future;
    peripheral.disconnectController.add(null);
    await Future.wait([checkStart, checkPause]);
    expect(peripheral.writes.map((p) => p[1]), [6, 1]);
    expect(gateway.status, isNull);
  });
  test(
      'GATT rejection (including firmware missing RESUME) closes uncertain link',
      () async {
    peripheral.publish(state: 5, reps: 8);
    peripheral.onWrite = (_) async {
      throw const TrackerException('GATT rejected write');
    };
    await expectLater(
        gateway.resumeCounting(), throwsA(isA<TrackerException>()));
    expect(peripheral.writes.last[1], 3);
    expect(gateway.connectedDevice, isNull);
  });
  test('Malformed packets close the connection and fail a pending command',
      () async {
    peripheral.onWrite = (_) async {
      peripheral.statusController.add([1, ...List.filled(15, 0)]);
    };
    await expectLater(
        gateway.startCounting(), throwsA(isA<TrackerException>()));
    expect(gateway.connectedDevice, isNull);
  });
  test('Sensor error is retained for the UI and RESET remains available',
      () async {
    peripheral.publish(state: 7, event: 8);
    await gateway.refreshStatus();
    expect(gateway.status!.state, TrackerState.error);
    expect(gateway.connectedDevice, isNotNull);
    await gateway.reset();
    expect(gateway.status!.state, TrackerState.idle);
  });
}

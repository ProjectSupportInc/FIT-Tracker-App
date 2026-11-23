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
    int reps = 0,
    int boot = 0x11223344,
    int session = 0,
    int revision = 1,
    int calibration = 0}) {
  final bytes = ByteData(20)
    ..setUint8(0, 2)
    ..setUint8(1, state)
    ..setUint8(2, event)
    ..setUint8(3, detail)
    ..setUint16(4, request, Endian.little)
    ..setUint16(6, reps, Endian.little)
    ..setUint32(8, boot, Endian.little)
    ..setUint32(12, session, Endian.little)
    ..setUint16(16, revision, Endian.little)
    ..setUint8(18, calibration);
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
  int boot = 0x11223344, session = 0, revision = 1, calibration = 0;
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
    if (event != 2 && packet[1] == 1) {
      session = ByteData.sublistView(Uint8List.fromList(packet))
          .getUint32(8, Endian.little);
    }
    if (event != 2 && packet[1] == 4) session = 0;
    snapshot = _status(
        state: state,
        reps: reps,
        event: event ?? (packet[1] == 6 ? 0 : 1),
        detail: detail,
        request: requestId ?? request(packet),
        boot: boot,
        session: session,
        revision: ++revision,
        calibration: calibration);
    statusController.add(snapshot);
  }

  void publish({int state = 0, int event = 0, int detail = 0, int reps = 0}) {
    if (state == 0 || state == 1 || state == 2 || event == 6) calibration = 0;
    if (event == 5) calibration = detail;
    if (state == 4) calibration = 3;
    snapshot = _status(
        state: state,
        event: event,
        detail: detail,
        reps: reps,
        boot: boot,
        session: session,
        revision: ++revision,
        calibration: calibration);
    statusController.add(snapshot);
  }

  void rep(int count) {
    final bytes = ByteData(18)
      ..setUint8(0, 2)
      ..setUint8(1, 1)
      ..setUint16(2, count, Endian.little)
      ..setUint32(4, 0x12345678, Endian.little)
      ..setUint32(8, boot, Endian.little)
      ..setUint32(12, session, Endian.little)
      ..setUint16(16, ++revision, Endian.little);
    repController.add(bytes.buffer.asUint8List());
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
    expect(peripheral.writes.single,
        [2, 6, 1, 0, 0x44, 0x33, 0x22, 0x11, 0, 0, 0, 0]);
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
        peripheral.writes.every((p) => p.length == 12 && p[4] == 0x44), isTrue);
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
  test('Late snapshots from an earlier session cannot replace a newer revision',
      () async {
    await gateway.startCounting(sessionId: 10);
    final old = List<int>.of(peripheral.snapshot);
    await gateway.reset();
    await gateway.startCounting(sessionId: 20);
    peripheral.statusController.add(old);
    expect(gateway.status!.sessionId, 20);
    peripheral.session = 10;
    peripheral.rep(99);
    await Future<void>.delayed(Duration.zero);
    expect(gateway.status!.repetitions, 0);
  });

  test('Calibration snapshot is recoverable without observing earlier events',
      () async {
    peripheral.session = 42;
    peripheral.publish(state: 3, event: 5, detail: 2);
    await gateway.disconnect();
    await gateway.connect(const TrackerDevice(id: 'esp32'));
    expect(gateway.status!.calibrationReps, 2);
    expect(gateway.status!.sessionId, 42);
  });

  test('Revision comparison works across the uint16 wrap', () async {
    peripheral.revision = 65533;
    await gateway.disconnect();
    peripheral.publish(state: 4, reps: 7);
    await gateway.connect(const TrackerDevice(id: 'esp32'));
    peripheral.revision = -1;
    peripheral.publish(state: 4, reps: 8);
    expect(gateway.status!.repetitions, 8);
  });

  test(
      'A silent connected peripheral is disconnected without waiting for a tap',
      () async {
    final silent = _Peripheral();
    final monitored = BleTrackerGateway(
        transport: silent,
        heartbeatInterval: const Duration(milliseconds: 20),
        freshnessTimeout: const Duration(milliseconds: 80),
        commandTimeout: const Duration(milliseconds: 300));
    addTearDown(monitored.dispose);
    await monitored.connect(const TrackerDevice(id: 'esp32'));
    silent.onWrite = (_) async {};
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(monitored.connectedDevice, isNull);
    expect(silent.disconnectCalls, greaterThan(1));
  });
}

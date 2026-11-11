import 'dart:async';
import 'dart:io';

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import '../domain/tracker_device.dart';
import '../domain/tracker_status.dart';
import 'ble_transport.dart';
import 'fitness_protocol.dart';

/// flutter_blue_plus adapter for the three-characteristic ESP32 service.
/// Its Android plugin requests Nearby Devices permissions on Android 12+ and
/// location permission/services on older Android versions during scan/connect.
class FlutterBleTransport implements BleTransport {
  final _statuses = StreamController<List<int>>.broadcast();
  final _reps = StreamController<List<int>>.broadcast();
  final _disconnections = StreamController<void>.broadcast();
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  BluetoothDevice? _device;
  BluetoothCharacteristic? _control;
  BluetoothCharacteristic? _status;
  bool _scanning = false;
  bool _disposed = false;

  @override
  Stream<List<int>> get statusPackets => _statuses.stream;
  @override
  Stream<List<int>> get repetitionPackets => _reps.stream;
  @override
  Stream<void> get disconnections => _disconnections.stream;

  Future<void> _requireAdapter() async {
    if (_disposed) {
      throw const TrackerException('The tracker connection has closed.');
    }
    if (!await FlutterBluePlus.isSupported) {
      throw const TrackerException(
          'Bluetooth Low Energy is not supported on this device.');
    }
    // Android 12+ can report UNKNOWN before CONNECT permission is granted.
    // Request first; waiting for adapterState before this would stall first use.
    // On older Android these permissions resolve to the manifest Bluetooth grant;
    // flutter_blue_plus subsequently requests legacy location access for scanning.
    if (Platform.isAndroid) {
      final permissions = await [
        Permission.bluetoothScan,
        Permission.bluetoothConnect
      ].request();
      if (permissions.values.any((status) => !status.isGranted)) {
        throw const TrackerException(
            'Allow Nearby devices access in app settings, then try again.');
      }
    }
    final state = await FlutterBluePlus.adapterState
        .where((state) => state != BluetoothAdapterState.unknown)
        .first
        .timeout(const Duration(seconds: 8));
    if (state == BluetoothAdapterState.unauthorized) {
      throw const TrackerException(
          'Allow Bluetooth access in your phone’s app settings.');
    }
    if (state != BluetoothAdapterState.on) {
      throw const TrackerException('Turn on Bluetooth, then scan again.');
    }
  }

  @override
  Future<List<TrackerDevice>> scan() async {
    await _requireAdapter();
    final devices = <String, TrackerDevice>{};
    final failed = Completer<void>();
    final subscription = FlutterBluePlus.onScanResults.listen((results) {
      for (final result in results) {
        final advertised = result.advertisementData.advName;
        devices[result.device.remoteId.str] = TrackerDevice(
          id: result.device.remoteId.str,
          name: advertised.isNotEmpty ? advertised : result.device.platformName,
          rssi: result.rssi,
        );
      }
    }, onError: (Object error, StackTrace stack) {
      if (!failed.isCompleted) failed.completeError(_friendly(error), stack);
    });
    // Attach the error listener before starting the scan (start itself can fail).
    final failure = failed.future;
    unawaited(failure.catchError((Object _) {}));
    try {
      _scanning = true;
      await FlutterBluePlus.startScan(
        withServices: [Guid(FitnessProtocol.serviceUuid)],
        timeout: const Duration(seconds: 7),
      );
      await Future.any<void>([
        FlutterBluePlus.isScanning.where((scanning) => !scanning).first,
        failure,
      ]);
      if (_disposed) {
        throw const TrackerException('The tracker connection has closed.');
      }
      final found = devices.values.toList()
        ..sort((a, b) => (b.rssi ?? -999).compareTo(a.rssi ?? -999));
      return found;
    } catch (error) {
      throw _friendly(error);
    } finally {
      _scanning = false;
      await subscription.cancel();
      await FlutterBluePlus.stopScan();
    }
  }

  @override
  Future<void> connect(TrackerDevice device) async {
    await _requireAdapter();
    await disconnect();
    final peripheral = BluetoothDevice.fromId(device.id);
    _device = peripheral;
    var wasConnected = false;
    _subscriptions.add(peripheral.connectionState.listen((state) {
      if (state == BluetoothConnectionState.connected) wasConnected = true;
      if (state == BluetoothConnectionState.disconnected &&
          wasConnected &&
          !_disposed) {
        _control = null;
        _status = null;
        _disconnections.add(null);
      }
    }));
    try {
      // Packets fit the default 23-byte ATT MTU; no large-MTU negotiation needed.
      await peripheral.connect(timeout: const Duration(seconds: 15), mtu: null);
      final services = await peripheral.discoverServices();
      final matching = services.where(
          (service) => service.uuid == Guid(FitnessProtocol.serviceUuid));
      if (matching.isEmpty) {
        throw const TrackerException(
            'This device does not expose the FitTracker BLE service.');
      }
      final service = matching.first;
      BluetoothCharacteristic find(String uuid) =>
          service.characteristics.firstWhere(
            (characteristic) => characteristic.uuid == Guid(uuid),
            orElse: () => throw const TrackerException(
                'The tracker firmware is missing a required BLE characteristic.'),
          );
      final control = find(FitnessProtocol.controlUuid);
      final status = find(FitnessProtocol.statusUuid);
      final telemetry = find(FitnessProtocol.telemetryUuid);
      if (!control.properties.write ||
          !status.properties.read ||
          !status.properties.notify ||
          !telemetry.properties.notify) {
        throw const TrackerException(
            'The tracker BLE characteristics have incompatible permissions.');
      }
      _control = control;
      _status = status;
      // Listen before enabling notifications so immediate firmware responses are retained.
      _subscriptions.add(status.onValueReceived.listen((bytes) {
        if (!_disposed) _statuses.add(bytes);
      }));
      _subscriptions.add(telemetry.onValueReceived.listen((bytes) {
        if (!_disposed) _reps.add(bytes);
      }));
      await status.setNotifyValue(true);
      await telemetry.setNotifyValue(true);
    } catch (error) {
      await disconnect();
      throw _friendly(error);
    }
  }

  @override
  Future<List<int>> readStatus() async {
    final characteristic = _status;
    if (characteristic == null) {
      throw const TrackerException('Connect a tracker first.');
    }
    try {
      return await characteristic.read(timeout: 8);
    } catch (error) {
      throw _friendly(error);
    }
  }

  @override
  Future<void> writeControl(List<int> packet) async {
    final characteristic = _control;
    if (characteristic == null) {
      throw const TrackerException(
          'The tracker disconnected. Please reconnect.');
    }
    try {
      await characteristic.write(packet, withoutResponse: false, timeout: 8);
    } catch (error) {
      throw _friendly(error);
    }
  }

  @override
  Future<void> disconnect() async {
    final device = _device;
    _device = null;
    _control = null;
    _status = null;
    final subscriptions = List<StreamSubscription<dynamic>>.of(_subscriptions);
    _subscriptions.clear();
    for (final subscription in subscriptions) {
      await subscription.cancel();
    }
    if (_scanning) await FlutterBluePlus.stopScan();
    if (device != null) {
      await device.disconnect();
    }
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await disconnect();
    await _statuses.close();
    await _reps.close();
    await _disconnections.close();
  }

  TrackerException _friendly(Object error) {
    if (error is TrackerException) return error;
    final message = error.toString().toLowerCase();
    if (message.contains('permission') || message.contains('unauthoriz')) {
      return const TrackerException(
          'Allow Nearby devices/Bluetooth access in app settings, then try again. On Android 11 or older, also allow location access.');
    }
    if (message.contains('location services')) {
      return const TrackerException(
          'Turn on Location services to scan for Bluetooth devices on this Android version.');
    }
    if (message.contains('turned on') || message.contains('adapter')) {
      return const TrackerException('Turn on Bluetooth, then try again.');
    }
    if (error is TimeoutException || message.contains('timeout')) {
      return const TrackerException(
          'The tracker did not respond. Move closer and reconnect.');
    }
    return const TrackerException(
        'Bluetooth communication failed. Check the tracker is powered on and reconnect.');
  }
}

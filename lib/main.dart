import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

// ---------------------------------------------------------------------------
// Colours taken from the HTML prototype
// ---------------------------------------------------------------------------
const kGreen = Color(0xFF173E35);
const kOrange = Color(0xFFDF754F);
const kBackground = Color(0xFFF7F9F4);
const kBorder = Color(0xFFE2E8DC);
const kMuted = Color(0xFF748075);

void main() => runApp(const RepformApp());

class RepformApp extends StatelessWidget {
  const RepformApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Repform',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: kBackground,
        colorScheme: ColorScheme.fromSeed(seedColor: kGreen, primary: kGreen),
        appBarTheme: const AppBarTheme(
          backgroundColor: kBackground,
          foregroundColor: kGreen,
          elevation: 0,
        ),
      ),
      home: const LoginScreen(),
    );
  }
}

// ---------------------------------------------------------------------------
// BLE service: finds "FitnessTrackerBLE", connects, and listens to the counter
// ---------------------------------------------------------------------------
enum BleStatus { idle, searching, connected, notConnected }

class BleService extends ChangeNotifier {
  static const String deviceName = 'FitnessTrackerBLE';
  // Must match SERVICE_UUID / CHAR_UUID in the laptop's Python script.
  static final Guid serviceUuid = Guid('A07498CA-AD5B-474E-940D-16F1FBE7E8CD');
  static final Guid charUuid = Guid('51FF12BB-3ED8-46E5-B4F9-D64E2FEC021B');

  BleStatus status = BleStatus.idle;
  String? errorDetail; // technical detail shown in small text
  int? value; // latest incrementing integer from the device
  String rawHex = ''; // latest raw bytes, handy for debugging
  String characteristicInfo = '';

  BluetoothDevice? _device;
  BluetoothCharacteristic? _char;
  StreamSubscription<BluetoothConnectionState>? _connSub;
  StreamSubscription<List<int>>? _valSub;
  Timer? _pollTimer;
  bool _busy = false;

  Future<bool> _ensurePermissions() async {
    final results = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
      Permission.locationWhenInUse, // only needed on Android 11 and older
    ].request();
    return results[Permission.bluetoothScan]!.isGranted &&
        results[Permission.bluetoothConnect]!.isGranted;
  }

  void _fail(String detail) {
    status = BleStatus.notConnected;
    errorDetail = detail;
    notifyListeners();
  }

  /// Look for the tracker (already connected to the phone, or advertising)
  /// and connect to it.
  Future<void> findAndConnect() async {
    if (_busy) return;
    _busy = true;
    await _cleanup();
    status = BleStatus.searching;
    errorDetail = null;
    value = null;
    rawHex = '';
    notifyListeners();

    try {
      if (!await FlutterBluePlus.isSupported) {
        _fail('This phone does not support Bluetooth LE.');
        return;
      }
      if (!await _ensurePermissions()) {
        _fail('Bluetooth permission was denied. Allow it in phone settings.');
        return;
      }

      // Make sure Bluetooth is switched on.
      var adapter = await FlutterBluePlus.adapterState.first;
      if (adapter != BluetoothAdapterState.on) {
        try {
          await FlutterBluePlus.turnOn();
        } catch (_) {}
        adapter = await FlutterBluePlus.adapterState
            .firstWhere((s) => s == BluetoothAdapterState.on)
            .timeout(const Duration(seconds: 10));
      }

      BluetoothDevice? found;

      // 1) Is it already connected to the phone at system level?
      final connected = await FlutterBluePlus.systemDevices([]);
      for (final d in connected) {
        if (d.platformName == deviceName) {
          found = d;
          break;
        }
      }

      // 2) Otherwise scan for it.
      if (found == null) {
        final completer = Completer<BluetoothDevice?>();
        final scanSub = FlutterBluePlus.onScanResults.listen((results) {
          for (final r in results) {
            final name = r.advertisementData.advName.isNotEmpty
                ? r.advertisementData.advName
                : r.device.platformName;
            final hasService =
                r.advertisementData.serviceUuids.contains(serviceUuid);
            if ((name == deviceName || hasService) && !completer.isCompleted) {
              completer.complete(r.device);
            }
          }
        });
        await FlutterBluePlus.startScan(timeout: const Duration(seconds: 8));
        // Wait until found, or the scan ends.
        FlutterBluePlus.isScanning
            .where((s) => s == false)
            .first
            .then((_) {
          if (!completer.isCompleted) completer.complete(null);
        });
        found = await completer.future;
        await FlutterBluePlus.stopScan();
        await scanSub.cancel();
      }

      if (found == null) {
        _fail('Could not find "$deviceName".');
        return;
      }

      // 3) Connect and find the data characteristic.
      _device = found;
      await found.connect(timeout: const Duration(seconds: 15));

      _connSub = found.connectionState.listen((s) {
        if (s == BluetoothConnectionState.disconnected &&
            status == BleStatus.connected) {
          _cleanup();
          _fail('The tracker disconnected.');
        }
      });

      final ok = await _setupCharacteristic(found);
      if (!ok) {
        await found.disconnect();
        _fail('Connected, but no readable data characteristic was found.');
        return;
      }

      status = BleStatus.connected;
      notifyListeners();
    } on TimeoutException {
      _fail('Timed out while connecting.');
    } catch (e) {
      _fail('Error: $e');
    } finally {
      _busy = false;
    }
  }

  /// Picks the first characteristic that can notify (or be read) and
  /// starts listening to it.
  Future<bool> _setupCharacteristic(BluetoothDevice device) async {
    final services = await device.discoverServices();

    BluetoothCharacteristic? notifyChar;
    BluetoothCharacteristic? readChar;

    for (final s in services) {
      final id = s.uuid.str.toLowerCase();
      // Skip the standard Generic Access / Generic Attribute services.
      if (id == '1800' || id == '1801') continue;
      for (final c in s.characteristics) {
        if (c.uuid == charUuid) {
          notifyChar = c;
          readChar = c;
          continue;
        }
        if (notifyChar == null &&
            (c.properties.notify || c.properties.indicate)) {
          notifyChar = c;
        }
        if (readChar == null && c.properties.read) {
          readChar = c;
        }
      }
    }

    final chosen = notifyChar ?? readChar;
    if (chosen == null) return false;
    _char = chosen;
    characteristicInfo =
        'service ${chosen.serviceUuid.str} / characteristic ${chosen.uuid.str}';

    _valSub = chosen.onValueReceived.listen(_onBytes);

    if (notifyChar != null) {
      await chosen.setNotifyValue(true);
    } else {
      // Not notifying: poll by reading twice per second.
      _pollTimer = Timer.periodic(const Duration(milliseconds: 500), (_) async {
        try {
          await chosen.read();
        } catch (_) {}
      });
    }
    // Get a first value straight away if possible.
    if (chosen.properties.read) {
      try {
        await chosen.read();
      } catch (_) {}
    }
    return true;
  }

  void _onBytes(List<int> bytes) {
    rawHex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ');
    value = _parse(bytes);
    notifyListeners();
  }

  /// Converts the bytes sent by the device into an integer.
  /// - Two or more ASCII digits (e.g. "123")   -> read as text
  /// - Otherwise                              -> little-endian unsigned integer
  int? _parse(List<int> b) {
    if (b.isEmpty) return null;
    if (b.length >= 2 && b.every((x) => x >= 0x30 && x <= 0x39)) {
      return int.tryParse(String.fromCharCodes(b));
    }
    var v = 0;
    final n = b.length > 6 ? 6 : b.length; // keep it safely inside a Dart int
    for (var i = 0; i < n; i++) {
      v |= b[i] << (8 * i);
    }
    return v;
  }

  Future<void> _cleanup() async {
    _pollTimer?.cancel();
    _pollTimer = null;
    await _valSub?.cancel();
    _valSub = null;
    await _connSub?.cancel();
    _connSub = null;
    _char = null;
  }

  Future<void> disconnect() async {
    await _cleanup();
    try {
      await _device?.disconnect();
    } catch (_) {}
    _device = null;
    status = BleStatus.idle;
    value = null;
    notifyListeners();
  }
}

final ble = BleService();

// ---------------------------------------------------------------------------
// Shared widgets
// ---------------------------------------------------------------------------
class Logo extends StatelessWidget {
  const Logo({super.key});
  @override
  Widget build(BuildContext context) {
    return const Text.rich(
      TextSpan(children: [
        TextSpan(text: '↗ ', style: TextStyle(color: kOrange)),
        TextSpan(text: 'repform'),
      ]),
      style: TextStyle(
          fontWeight: FontWeight.w900,
          fontSize: 23,
          letterSpacing: -1,
          color: kGreen),
    );
  }
}

class PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool secondary;
  const PrimaryButton(
      {super.key,
      required this.label,
      required this.onPressed,
      this.secondary = false});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: FilledButton(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: secondary ? const Color(0xFFEAF0E1) : kGreen,
          foregroundColor: secondary ? kGreen : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 1. Login screen (no credentials needed for now)
// ---------------------------------------------------------------------------
class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Logo(),
              const SizedBox(height: 28),
              const Text('WELCOME',
                  style: TextStyle(
                      fontSize: 10,
                      letterSpacing: 1.6,
                      fontWeight: FontWeight.bold,
                      color: kMuted)),
              const SizedBox(height: 8),
              const Text('Your training,\nin one place.',
                  style: TextStyle(
                      fontSize: 29,
                      fontWeight: FontWeight.bold,
                      letterSpacing: -1,
                      color: kGreen)),
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                    color: kGreen, borderRadius: BorderRadius.circular(20)),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Every rep matters.',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 19,
                            fontWeight: FontWeight.bold)),
                    SizedBox(height: 8),
                    Text('A simple connection between you and your coach.',
                        style: TextStyle(color: Color(0xFFD4DFD0))),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              const TextField(
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                    labelText: 'Email', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 14),
              const TextField(
                obscureText: true,
                decoration: InputDecoration(
                    labelText: 'Password', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 18),
              PrimaryButton(
                label: 'OK',
                onPressed: () => Navigator.of(context).pushReplacement(
                  MaterialPageRoute(builder: (_) => const HomeScreen()),
                ),
              ),
              const SizedBox(height: 14),
              const Center(
                child: Text('No credentials required for now.',
                    style: TextStyle(color: kMuted, fontSize: 13)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 2. Home: checks the device, then shows exercises
// ---------------------------------------------------------------------------
class Exercise {
  final String name;
  final int targetReps;
  const Exercise(this.name, this.targetReps);
}

const exercises = [
  Exercise('Dumbbell curl', 10),
  Exercise('Bench press', 12),
  Exercise('Squat', 15),
  Exercise('Shoulder press', 10),
];

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    ble.findAndConnect();
  }

  @override
  void dispose() {
    ble.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Logo()),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: ble,
          builder: (context, _) {
            switch (ble.status) {
              case BleStatus.idle:
              case BleStatus.searching:
                return const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: kOrange),
                      SizedBox(height: 16),
                      Text('Looking for FitnessTrackerBLE…',
                          style: TextStyle(color: kMuted)),
                    ],
                  ),
                );
              case BleStatus.notConnected:
                return _NotConnected(detail: ble.errorDetail);
              case BleStatus.connected:
                return _ExerciseList();
            }
          },
        ),
      ),
    );
  }
}

class _NotConnected extends StatelessWidget {
  final String? detail;
  const _NotConnected({this.detail});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.bluetooth_disabled, size: 64, color: kOrange),
          const SizedBox(height: 18),
          const Text('Fitness Tracker is not connected connect please!',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 20, fontWeight: FontWeight.bold, color: kGreen)),
          if (detail != null) ...[
            const SizedBox(height: 10),
            Text(detail!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: kMuted, fontSize: 12)),
          ],
          const SizedBox(height: 24),
          PrimaryButton(label: 'Try again', onPressed: ble.findAndConnect),
        ],
      ),
    );
  }
}

class _ExerciseList extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
              color: const Color(0xFFEDF2E5),
              borderRadius: BorderRadius.circular(20)),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.bluetooth_connected, size: 16, color: kGreen),
              SizedBox(width: 6),
              Text('FitnessTrackerBLE connected',
                  style: TextStyle(fontSize: 12, color: kGreen)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const Text('Choose an exercise',
            style: TextStyle(
                fontSize: 29,
                fontWeight: FontWeight.bold,
                letterSpacing: -1,
                color: kGreen)),
        const SizedBox(height: 12),
        for (final e in exercises)
          Card(
            color: Colors.white,
            elevation: 0,
            margin: const EdgeInsets.symmetric(vertical: 6),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(17),
              side: const BorderSide(color: kBorder),
            ),
            child: ListTile(
              contentPadding: const EdgeInsets.all(14),
              title: Text(e.name,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, color: kGreen)),
              subtitle: Text('Target: ${e.targetReps} repetitions',
                  style: const TextStyle(color: kMuted)),
              trailing: const Icon(Icons.chevron_right, color: kMuted),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => ExerciseScreen(exercise: e)),
              ),
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 3. Exercise screen: shows the live incrementing value from the device
// ---------------------------------------------------------------------------
class ExerciseScreen extends StatelessWidget {
  final Exercise exercise;
  const ExerciseScreen({super.key, required this.exercise});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(exercise.name)),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: ble,
          builder: (context, _) {
            if (ble.status != BleStatus.connected) {
              return _NotConnected(detail: ble.errorDetail);
            }
            return Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Text('Target: ${exercise.targetReps} repetitions',
                      style: const TextStyle(color: kMuted)),
                  const Spacer(),
                  Container(
                    width: 230,
                    height: 230,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: kOrange, width: 9),
                    ),
                    alignment: Alignment.center,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(ble.value?.toString() ?? '--',
                            style: const TextStyle(
                                fontSize: 76,
                                fontWeight: FontWeight.bold,
                                letterSpacing: -4,
                                color: kGreen)),
                        const Text('value from device',
                            style: TextStyle(color: kMuted, fontSize: 13)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    ble.value == null
                        ? 'Waiting for data…'
                        : 'Live from FitnessTrackerBLE',
                    style: const TextStyle(color: kMuted),
                  ),
                  const SizedBox(height: 12),
                  Text('raw bytes: ${ble.rawHex.isEmpty ? '-' : ble.rawHex}\n${ble.characteristicInfo}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: kMuted, fontSize: 10)),
                  const Spacer(),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

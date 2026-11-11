import 'dart:async';

import '../domain/tracker_device.dart';
import '../domain/tracker_status.dart';
import 'ble_transport.dart';
import 'fitness_protocol.dart';
import 'flutter_ble_transport.dart';
import 'tracker_gateway.dart';

/// Real workout gateway: sends versioned commands and waits for matching firmware
/// acknowledgements. A successful GATT write alone never means an action succeeded.
class BleTrackerGateway implements TrackerGateway {
  BleTrackerGateway(
      {BleTransport? transport,
      this.commandTimeout = const Duration(seconds: 8)})
      : _transport = transport ?? FlutterBleTransport() {
    _subscriptions.add(_transport.statusPackets
        .listen(_onStatusPacket, onError: (Object _) => _protocolFailure()));
    _subscriptions.add(_transport.repetitionPackets
        .listen(_onRepPacket, onError: (Object _) => _protocolFailure()));
    _subscriptions
        .add(_transport.disconnections.listen((_) => _lostConnection()));
  }

  final BleTransport _transport;
  final Duration commandTimeout;
  final _statuses = StreamController<TrackerStatus?>.broadcast();
  final _repetitions = StreamController<int>.broadcast();
  final List<StreamSubscription<dynamic>> _subscriptions = [];
  Future<void> _queue = Future<void>.value();
  TrackerDevice? _device;
  TrackerStatus? _status;
  _PendingCommand? _pending;
  int _requestId = 0;
  int _generation = 0;
  int _lastReps = 0;
  bool _disposed = false;

  @override
  Stream<int> get repetitionCounts => _repetitions.stream;
  @override
  Stream<TrackerStatus?> get statuses => _statuses.stream;
  @override
  TrackerStatus? get status => _status;
  @override
  TrackerDevice? get connectedDevice => _device;

  /// One command at a time prevents a later ACK from satisfying an earlier action.
  Future<T> _serial<T>(Future<T> Function() action) {
    final result = _queue.then((_) {
      if (_disposed) {
        throw const TrackerException('The tracker connection has closed.');
      }
      return action();
    });
    _queue = result.then<void>((_) {}, onError: (Object _, StackTrace __) {});
    return result;
  }

  @override
  Future<List<TrackerDevice>> scan() => _serial(_transport.scan);

  @override
  Future<void> connect(TrackerDevice device) => _serial(() async {
        await disconnect();
        final generation = _generation;
        _device = device;
        try {
          await _transport.connect(device);
          _checkGeneration(generation);
          // Read returns the current snapshot, even before a command has been sent.
          final initial =
              FitnessProtocol.decodeStatus(await _transport.readStatus());
          _checkGeneration(generation);
          _accept(initial);
          await _send(TrackerCommand.getStatus, 0);
        } catch (error) {
          await disconnect();
          if (error is FormatException) {
            throw const TrackerException(
                'The tracker uses an incompatible BLE protocol. Update its firmware.');
          }
          rethrow;
        }
      });

  Future<void> _action(Future<void> Function() action) {
    // A command queued before a disconnect must never act on a newly connected device.
    final generation = _generation;
    return _serial(() async {
      _checkGeneration(generation);
      await action();
    });
  }

  @override
  Future<void> selectExercise({required String exerciseKind}) =>
      _action(() async {
        await _send(TrackerCommand.select, exerciseIdForKind(exerciseKind));
      });

  @override
  Future<void> beginCalibration({required String exerciseKind}) =>
      _action(() async {
        final exerciseId = exerciseIdForKind(exerciseKind);
        if (_status?.exerciseId != exerciseId) {
          throw const TrackerException(
              'Select this exercise on the tracker before calibrating.');
        }
        await _send(TrackerCommand.calibrate, exerciseId);
      });

  @override
  Future<void> refreshStatus() => _action(() async {
        await _send(TrackerCommand.getStatus, 0);
      });

  @override
  Future<void> startCounting({required String exerciseKind}) =>
      _action(() async {
        final exerciseId = exerciseIdForKind(exerciseKind);
        if (_status?.exerciseId != exerciseId) {
          throw const TrackerException(
              'Select this exercise on the tracker before starting.');
        }
        await _send(TrackerCommand.start, exerciseId);
      });

  @override
  Future<void> pauseCounting() => _action(() async {
        await _send(TrackerCommand.pause, _selectedExercise());
      });

  @override
  Future<void> resumeCounting() => _action(() async {
        // START from PAUSED resumes without resetting the firmware count.
        await _send(TrackerCommand.start, _selectedExercise());
      });

  @override
  Future<void> stopCounting() => _action(() async {
        if (_status?.exerciseId == 0) return;
        await _send(TrackerCommand.finish, _selectedExercise());
      });

  int _selectedExercise() {
    final id = _status?.exerciseId ?? 0;
    if (id == 0) throw const TrackerException('Select an exercise first.');
    return id;
  }

  void _checkGeneration(int generation) {
    if (_device == null || generation != _generation) {
      throw const TrackerException(
          'The tracker disconnected. Reconnect before continuing.');
    }
  }

  Future<TrackerStatus> _send(TrackerCommand command, int exerciseId) async {
    _checkGeneration(_generation);
    _requestId = (_requestId % 65535) + 1;
    final pending = _PendingCommand(_requestId, exerciseId, command);
    _pending = pending;
    // Attach an error listener now, including when a disconnect occurs during write().
    final response = pending.completer.future;
    unawaited(
        response.then<void>((_) {}, onError: (Object _, StackTrace __) {}));
    try {
      await _transport
          .writeControl(
              FitnessProtocol.command(command, pending.requestId, exerciseId))
          .timeout(commandTimeout);
      final status = await response.timeout(commandTimeout);
      // GET_STATUS reports the existing sensor/storage fault, not a rejected query.
      // Keep the connection available so setup can show and recover that fault.
      if (status.result != 0 && command != TrackerCommand.getStatus) {
        throw TrackerException(FitnessProtocol.resultMessage(status.result));
      }
      if (!_expectedState(command, status.state)) {
        throw const TrackerException(
            'The tracker returned an unexpected state. Refresh and try again.');
      }
      return status;
    } on TimeoutException {
      // The action may have reached the device. Disconnect makes firmware pause,
      // instead of silently retrying START and risking an unknown workout state.
      await disconnect();
      throw const TrackerException(
          'The tracker did not confirm the action. Reconnect and try again.');
    } catch (error) {
      if (!pending.completer.isCompleted) {
        // A failed write has an uncertain outcome; reset this BLE session.
        await disconnect();
      }
      rethrow;
    } finally {
      if (identical(_pending, pending)) _pending = null;
    }
  }

  bool _expectedState(TrackerCommand command, TrackerState state) =>
      switch (command) {
        TrackerCommand.select =>
          state == TrackerState.selected || state == TrackerState.ready,
        TrackerCommand.calibrate => state == TrackerState.calibrating,
        TrackerCommand.start => state == TrackerState.running,
        TrackerCommand.pause => state == TrackerState.paused,
        TrackerCommand.finish => state == TrackerState.ready ||
            state == TrackerState.selected ||
            state == TrackerState.idle,
        TrackerCommand.getStatus => true,
      };

  void _onStatusPacket(List<int> bytes) {
    if (_disposed || _device == null) return;
    try {
      final next = FitnessProtocol.decodeStatus(bytes);
      final pending = _pending;
      final matches = pending != null &&
          next.requestId == pending.requestId &&
          (pending.command == TrackerCommand.getStatus ||
              next.exerciseId == pending.exerciseId ||
              next.result != 0);
      // Old ACKs (including read echoes) cannot change a newer command's state.
      if (next.requestId != 0 && !matches) return;
      _accept(next);
      if (matches && !pending.completer.isCompleted) {
        pending.completer.complete(next);
      }
    } on FormatException {
      _protocolFailure();
    }
  }

  void _accept(TrackerStatus next) {
    _status = next;
    _lastReps = next.repetitions;
    _statuses.add(next);
    // Calibration progress is separate from workout reps. FINISH still publishes
    // the authoritative final total, even though its state has become READY.
    if (next.state != TrackerState.calibrating) {
      _repetitions.add(next.repetitions);
    }
  }

  void _onRepPacket(List<int> bytes) {
    if (_disposed || _device == null) return;
    try {
      final event = FitnessProtocol.decodeRepetition(bytes);
      final current = _status;
      if (current == null ||
          event.exerciseId != current.exerciseId ||
          (current.state != TrackerState.running &&
              current.state != TrackerState.paused) ||
          event.repetitions < _lastReps) {
        return;
      }
      _lastReps = event.repetitions;
      _repetitions.add(event.repetitions);
    } on FormatException {
      _protocolFailure();
    }
  }

  void _protocolFailure() {
    if (_disposed || _device == null) return;
    const error = TrackerException(
        'Invalid data received from the tracker. Reconnect with compatible firmware.');
    _lostConnection(error);
    unawaited(_transport.disconnect().catchError((Object _) {}));
  }

  void _lostConnection([TrackerException? error]) {
    _generation++;
    _device = null;
    _status = null;
    _lastReps = 0;
    final pending = _pending;
    _pending = null;
    if (pending != null && !pending.completer.isCompleted) {
      pending.completer.completeError(error ??
          const TrackerException(
              'The tracker disconnected. Please reconnect.'));
    }
    if (!_disposed) _statuses.add(null);
  }

  @override
  Future<void> disconnect() async {
    _lostConnection();
    await _transport.disconnect();
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _lostConnection();
    for (final subscription in _subscriptions) {
      await subscription.cancel();
    }
    await _transport.dispose();
    await _statuses.close();
    await _repetitions.close();
  }
}

class _PendingCommand {
  _PendingCommand(this.requestId, this.exerciseId, this.command);
  final int requestId;
  final int exerciseId;
  final TrackerCommand command;
  final completer = Completer<TrackerStatus>();
}

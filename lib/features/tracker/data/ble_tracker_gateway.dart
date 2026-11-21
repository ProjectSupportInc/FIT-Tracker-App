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
          await _send(TrackerCommand.getStatus);
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
  Future<void> refreshStatus() => _action(() async {
        await _send(TrackerCommand.getStatus);
      });

  @override
  Future<void> startCounting() => _action(() async {
        await _send(TrackerCommand.start);
      });

  @override
  Future<void> pauseCounting() => _action(() async {
        await _send(TrackerCommand.pause);
      });

  @override
  Future<void> resumeCounting() => _action(() async {
        await _send(TrackerCommand.resume);
      });

  @override
  Future<void> reset() => _action(() async {
        await _send(TrackerCommand.reset);
      });

  @override
  Future<void> stopCounting() => _action(() async {
        // FINISH is not idempotent in this firmware. Query before retrying it.
        await _send(TrackerCommand.getStatus);
        if (_status!.state == TrackerState.finished ||
            _status!.state == TrackerState.idle) {
          return;
        }
        await _send(TrackerCommand.finish);
      });

  void _checkGeneration(int generation) {
    if (_device == null || generation != _generation) {
      throw const TrackerException(
          'The tracker disconnected. Reconnect before continuing.');
    }
  }

  Future<TrackerStatus> _send(TrackerCommand command) async {
    _checkGeneration(_generation);
    _requestId = (_requestId % 65535) + 1;
    final pending = _PendingCommand(_requestId, command);
    _pending = pending;
    // Attach an error listener now, including when a disconnect occurs during write().
    final response = pending.completer.future;
    unawaited(
        response.then<void>((_) {}, onError: (Object _, StackTrace __) {}));
    try {
      await _transport
          .writeControl(FitnessProtocol.command(command, pending.requestId))
          .timeout(commandTimeout);
      final status = await response.timeout(commandTimeout);
      if (status.event == TrackerEvent.commandRejected) {
        throw TrackerException(FitnessProtocol.resultMessage(status.detail));
      }
      if (!_expectedState(command, status.state)) {
        throw const TrackerException(
            'The tracker returned an unexpected state. Refresh and try again.');
      }
      return status;
    } on TimeoutException {
      // A timeout leaves the command outcome unknown. This firmware continues
      // running after disconnect, so the UI must not claim the device stopped.
      await disconnect();
      throw TrackerException(pending.sawWrongAck
          ? 'The firmware replied with the command number instead of the request ID. '
              'Correct the firmware acknowledgement before continuing. '
              'The tracker may still be running.'
          : 'The tracker did not confirm the action. It may still be running. '
              'Reconnect to check its state.');
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
        TrackerCommand.start => state == TrackerState.waitPickup,
        TrackerCommand.pause => state == TrackerState.paused,
        TrackerCommand.resume => state.isActive,
        TrackerCommand.reset => state == TrackerState.idle,
        TrackerCommand.finish => state == TrackerState.finished,
        TrackerCommand.getStatus => true,
      };

  void _onStatusPacket(List<int> bytes) {
    if (_disposed || _device == null) return;
    try {
      final next = FitnessProtocol.decodeStatus(bytes);
      final pending = _pending;
      final matches = pending != null &&
          next.requestId == pending.requestId &&
          (next.event == TrackerEvent.commandRejected ||
              (pending.command == TrackerCommand.getStatus
                  ? next.event == TrackerEvent.none
                  : next.event == TrackerEvent.commandOk));
      if (pending != null &&
          next.event == TrackerEvent.commandOk &&
          next.requestId == pending.command.code &&
          !matches) {
        pending.sawWrongAck = true;
      }
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
    var progress = _status?.calibrationReps ?? 0;
    if (next.state == TrackerState.idle ||
        next.state == TrackerState.waitPickup ||
        next.state == TrackerState.settling ||
        next.event == TrackerEvent.calibrationReset) {
      progress = 0;
    } else if (next.event == TrackerEvent.calibrationRep) {
      progress = next.detail;
    } else if (next.state == TrackerState.running ||
        next.event == TrackerEvent.templateLocked) {
      progress = TrackerStatus.calibrationTarget;
    }
    _status = next.copyWith(calibrationReps: progress);
    _lastReps = next.repetitions;
    _statuses.add(_status);
    _repetitions.add(next.repetitions);
  }

  void _onRepPacket(List<int> bytes) {
    if (_disposed || _device == null) return;
    try {
      final event = FitnessProtocol.decodeRepetition(bytes);
      final current = _status;
      if (current == null ||
          (current.state != TrackerState.running &&
              current.state != TrackerState.paused) ||
          event.repetitions < _lastReps) {
        return;
      }
      _lastReps = event.repetitions;
      // Heartbeat telemetry can recover a lost rep notification. Keep the
      // snapshot current too, so later pause/finish checks see the same total.
      _status = current.copyWith(repetitions: event.repetitions);
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
  _PendingCommand(this.requestId, this.command);
  final int requestId;
  final TrackerCommand command;
  bool sawWrongAck = false;
  final completer = Completer<TrackerStatus>();
}

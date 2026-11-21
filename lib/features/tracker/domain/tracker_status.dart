/// Wire values mirror ft_state_t in the FreeRTOS firmware.
enum TrackerState {
  idle,
  waitPickup,
  settling,
  calibrating,
  running,
  paused,
  finished,
  error;

  bool get isPreparing =>
      this == waitPickup || this == settling || this == calibrating;
  bool get isActive => isPreparing || this == running;
}

/// A status is either a command reply or an unsolicited detector/heartbeat event.
enum TrackerEvent {
  none,
  commandOk,
  commandRejected,
  handlingDetected,
  holdComplete,
  calibrationRep,
  calibrationReset,
  templateLocked,
  sensorError
}

class TrackerStatus {
  const TrackerStatus({
    required this.state,
    this.repetitions = 0,
    this.event = TrackerEvent.none,
    this.detail = 0,
    this.requestId = 0,
    this.calibrationReps = 0,
  });

  final TrackerState state;
  final int repetitions;
  final TrackerEvent event;
  final int detail;

  /// Zero means an unsolicited update, never a command acknowledgement.
  final int requestId;

  /// Progress remembered from events on this connection; not a persisted profile.
  /// Heartbeats do not contain this field. Unknown/missed progress stays at zero.
  final int calibrationReps;
  static const calibrationTarget = 3;

  TrackerStatus copyWith({int? repetitions, int? calibrationReps}) =>
      TrackerStatus(
        state: state,
        repetitions: repetitions ?? this.repetitions,
        event: event,
        detail: detail,
        requestId: requestId,
        calibrationReps: calibrationReps ?? this.calibrationReps,
      );
}

class TrackerException implements Exception {
  const TrackerException(this.message);
  final String message;
  @override
  String toString() => message;
}

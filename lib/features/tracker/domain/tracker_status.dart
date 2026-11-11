/// Sensor states reported by the ESP32, in the same order as ft_state_t.
enum TrackerState { idle, selected, calibrating, ready, running, paused, error }

/// One authoritative snapshot from the firmware's Status characteristic.
/// Screens consume this through WorkoutViewModel rather than predicting whether
/// a command succeeded or pretending that a calibration profile was saved.
class TrackerStatus {
  const TrackerStatus({
    required this.state,
    required this.exerciseId,
    required this.sensorReady,
    required this.profileAvailable,
    required this.repetitions,
    required this.calibrationReps,
    this.calibrationTarget = 3,
    this.result = 0,
    this.requestId = 0,
  });

  final TrackerState state;
  final int exerciseId;
  final bool sensorReady;
  final bool profileAvailable;
  final int repetitions;
  final int calibrationReps;
  final int calibrationTarget;

  /// Zero means success; nonzero values are firmware rejection/error codes.
  final int result;

  /// Matches a Control request, or zero for an unsolicited status notification.
  final int requestId;
}

/// Stable movement IDs shared with firmware. They are not workout/session IDs.
/// Aliases keep existing plans and tests compatible without comparing UI labels.
int exerciseIdForKind(String kind) => switch (kind.trim().toLowerCase()) {
      'curl' || 'dumbbell curl' => 1,
      'bench' || 'bench press' => 2,
      'push-up' || 'push-ups' || 'pushup' || 'pushups' => 3,
      'shoulder press' => 4,
      'row' || 'dumbbell row' => 5,
      'squat' || 'squats' => 6,
      _ => throw const TrackerException(
          'This exercise is not supported by the tracker.'),
    };

/// User-readable BLE/protocol failure; UI can display message without a stack trace.
class TrackerException implements Exception {
  const TrackerException(this.message);
  final String message;
  @override
  String toString() => message;
}

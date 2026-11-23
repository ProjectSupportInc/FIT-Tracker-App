import '../../tracker/domain/tracker_status.dart';
import 'workout_models.dart';

/// Persisted before START so an uncertain command can be recovered after a crash.
class ActiveExercise {
  const ActiveExercise(
      {required this.workoutId,
      required this.exerciseId,
      required this.attemptId,
      required this.deviceId,
      required this.deviceName,
      required this.bootId,
      required this.sessionId,
      this.repetitions = 0,
      this.state = TrackerState.waitPickup,
      this.runId,
      this.finalResult});

  final String workoutId, exerciseId, attemptId, deviceId, deviceName;
  final int bootId, sessionId, repetitions;
  final TrackerState state;
  final String? runId;
  final ExerciseResult? finalResult;

  ActiveExercise copyWith(
          {int? repetitions,
          TrackerState? state,
          ExerciseResult? finalResult}) =>
      ActiveExercise(
          workoutId: workoutId,
          exerciseId: exerciseId,
          attemptId: attemptId,
          deviceId: deviceId,
          deviceName: deviceName,
          bootId: bootId,
          sessionId: sessionId,
          repetitions: repetitions ?? this.repetitions,
          state: state ?? this.state,
          runId: runId,
          finalResult: finalResult ?? this.finalResult);

  Map<String, dynamic> toJson() => {
        'workoutId': workoutId,
        'exerciseId': exerciseId,
        'attemptId': attemptId,
        'deviceId': deviceId,
        'deviceName': deviceName,
        'bootId': bootId,
        'sessionId': sessionId,
        'repetitions': repetitions,
        'state': state.name,
        'runId': runId,
        'finalResult': finalResult?.toJson()
      };

  factory ActiveExercise.fromJson(Map<String, dynamic> value) {
    final boot = value['bootId'] as int;
    final session = value['sessionId'] as int;
    final reps = value['repetitions'] as int;
    if (boot <= 0 ||
        boot > 0xffffffff ||
        session <= 0 ||
        session > 0xffffffff ||
        reps < 0 ||
        reps > 65535) {
      throw const FormatException('Invalid saved tracker session.');
    }
    return ActiveExercise(
        workoutId: value['workoutId'] as String,
        exerciseId: value['exerciseId'] as String,
        attemptId: value['attemptId'] as String,
        deviceId: value['deviceId'] as String,
        deviceName: value['deviceName'] as String,
        bootId: boot,
        sessionId: session,
        repetitions: reps,
        state: TrackerState.values.byName(value['state'] as String),
        runId: value['runId'] as String?,
        finalResult: value['finalResult'] == null
            ? null
            : ExerciseResult.fromJson(
                value['finalResult'] as Map<String, dynamic>));
  }
}

/// An optional repeat has its own progress; the original completion stays intact.
class WorkoutRepeat {
  const WorkoutRepeat(
      {required this.id,
      required this.workoutId,
      required this.exerciseIds,
      this.index = 0});
  final String id, workoutId;
  final List<String> exerciseIds;
  final int index;
  String get exerciseId => exerciseIds[index];
  WorkoutRepeat? advance() => index + 1 == exerciseIds.length
      ? null
      : WorkoutRepeat(
          id: id,
          workoutId: workoutId,
          exerciseIds: exerciseIds,
          index: index + 1);
  Map<String, dynamic> toJson() => {
        'id': id,
        'workoutId': workoutId,
        'exerciseIds': exerciseIds,
        'index': index
      };
  factory WorkoutRepeat.fromJson(Map<String, dynamic> value) {
    final ids = (value['exerciseIds'] as List).cast<String>();
    final index = value['index'] as int;
    if (ids.isEmpty || index < 0 || index >= ids.length) {
      throw const FormatException('Invalid repeat progress.');
    }
    return WorkoutRepeat(
        id: value['id'] as String,
        workoutId: value['workoutId'] as String,
        exerciseIds: ids,
        index: index);
  }
}

class WorkoutJournal {
  const WorkoutJournal({this.active, this.repeat});
  final ActiveExercise? active;
  final WorkoutRepeat? repeat;
  Map<String, dynamic> toJson() =>
      {'active': active?.toJson(), 'repeat': repeat?.toJson()};
  factory WorkoutJournal.fromJson(Map<String, dynamic> value) => WorkoutJournal(
      active: value['active'] == null
          ? null
          : ActiveExercise.fromJson(value['active'] as Map<String, dynamic>),
      repeat: value['repeat'] == null
          ? null
          : WorkoutRepeat.fromJson(value['repeat'] as Map<String, dynamic>));
}

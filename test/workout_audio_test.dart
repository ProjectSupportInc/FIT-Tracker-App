import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repform_app/features/tracker/domain/tracker_status.dart';
import 'package:repform_app/features/workouts/domain/workout_models.dart';
import 'package:repform_app/features/workouts/presentation/workout_audio.dart';
import 'package:repform_app/features/workouts/presentation/workout_view_model.dart';
import 'workout_view_model_test.dart' show TestRepository, TestTracker;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('fittracker/test-audio');
  final calls = <MethodCall>[];
  late TestTracker tracker;
  late WorkoutViewModel vm;
  late WorkoutAudio audio;
  const exercise = ExercisePlan(
      id: 'curl', name: 'Curl', kind: 'curl', targetReps: 10, coachTip: '');
  final plan = WorkoutPlan(
      id: 'today',
      title: 'Today',
      description: '',
      scheduledAt: DateTime.now(),
      exercises: const [exercise]);
  Future<void> flush() => Future<void>.delayed(Duration.zero);
  List<Map<dynamic, dynamic>> cues() => calls
      .where((c) => c.method == 'cue')
      .map((c) => c.arguments as Map<dynamic, dynamic>)
      .toList();
  setUp(() async {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'getSettings') {
        return {'mode': 'voice', 'speakReps': false, 'voiceAvailable': true};
      }
      return null;
    });
    tracker = TestTracker();
    vm = WorkoutViewModel(repository: TestRepository(plan), tracker: tracker);
    await vm.load();
    audio = WorkoutAudio(vm, channel: channel)..setWorkoutVisible(true);
    await flush();
    await vm.connect((await tracker.scan()).first);
    await vm.prepareExercise(exercise);
    await vm.startExercise(plan, exercise);
    await flush();
  });
  tearDown(() async {
    audio.dispose();
    vm.dispose();
    await flush();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
      'Guidance follows phases and accepted reps, without replaying heartbeats',
      () async {
    expect(cues().last['text'], 'Take your starting position.');
    tracker.publish(TrackerState.settling);
    tracker.publish(TrackerState.calibrating);
    tracker.publish(TrackerState.calibrating, calReps: 1);
    await flush();
    expect(cues().last['text'], 'One recorded. Repeat the same movement.');
    final count = cues().length;
    await tracker.refreshStatus();
    await tracker.refreshStatus();
    await flush();
    expect(cues(), hasLength(count));
    tracker.completeCalibration();
    tracker.emitReps(4);
    await flush();
    expect(cues().last['tone'], 'rep');
    expect(cues().last['text'], isNull);
  });

  test(
      'Mute suppresses cues and enabling spoken counts announces only the latest count',
      () async {
    await audio.setPreferences(mode: WorkoutAudioMode.muted);
    final count = cues().length;
    tracker.completeCalibration();
    tracker.emitReps(5);
    await flush();
    expect(cues(), hasLength(count));
    await audio.setPreferences(mode: WorkoutAudioMode.voice, speakReps: true);
    tracker.emitReps(8);
    await flush();
    expect(cues().last['text'], '8');
    expect(cues().where((c) => c['text'] == '6' || c['text'] == '7'), isEmpty);
    tracker.emitReps(10);
    await flush();
    expect(cues().last['text'], contains('Target reached'));
  });

  test(
      'Backgrounding and leaving the workout stop sound and release the screen',
      () async {
    tracker.completeCalibration();
    await flush();
    audio.setForeground(false);
    final count = cues().length;
    tracker.emitReps(4);
    await flush();
    expect(cues(), hasLength(count));
    expect(calls.where((c) => c.method == 'stop'), isNotEmpty);
    expect(calls.where((c) => c.method == 'setActive').last.arguments, isFalse);
    audio.setForeground(true);
    audio.setWorkoutVisible(false);
    await flush();
    expect(calls.where((c) => c.method == 'setActive').last.arguments, isFalse);
  });

  test(
      'An inactivity reset announces a fresh calibration without claiming a rep',
      () async {
    tracker.publish(TrackerState.calibrating, calReps: 1);
    tracker.emitStatus(TrackerStatus(
        state: TrackerState.waitPickup,
        event: TrackerEvent.calibrationReset,
        detail: 1,
        bootId: tracker.bootId,
        sessionId: tracker.sessionId));
    await flush();
    expect(
        cues().last['text'], 'Calibration reset. Take your starting position.');
    expect(vm.liveReps, 0);
  });
}

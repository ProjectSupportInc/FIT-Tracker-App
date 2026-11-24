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
        return {'mode': 'voice', 'speakReps': true, 'voiceAvailable': true};
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

  test('Only setup cues are spoken; calibration and normal reps beep once',
      () async {
    expect(cues().last['text'], 'Waiting for start.');
    tracker.publish(TrackerState.settling);
    expect(cues().last['text'], 'Hold position.');
    tracker.publish(TrackerState.calibrating);
    expect(cues().last['text'], 'Begin your reps.');
    for (final rep in [1, 2, 3]) {
      tracker.publish(TrackerState.calibrating, calReps: rep);
      expect(cues().last['tone'], 'rep');
      expect(cues().last['text'], isNull);
    }
    final count = cues().length;
    tracker.completeCalibration();
    await tracker.refreshStatus();
    expect(cues(), hasLength(count));
    tracker.emitReps(4);
    await tracker.refreshStatus();
    await flush();
    expect(cues(), hasLength(count + 1));
    expect(cues().last['tone'], 'rep');
    expect(cues().last['text'], isNull);
  });

  test('Two remaining and target cues retain the beep and never repeat',
      () async {
    tracker.completeCalibration();
    tracker.emitReps(7);
    expect(cues().last['text'], isNull);
    tracker.emitReps(8);
    expect(cues().last['text'], 'Two more left.');
    expect(cues().last['tone'], 'rep');
    tracker.emitReps(9);
    expect(cues().last['text'], isNull);
    tracker.emitReps(10);
    expect(cues().last['text'], 'Good job.');
    expect(cues().last['tone'], 'rep');
    tracker.emitReps(11);
    await vm.togglePause();
    await vm.togglePause();
    tracker.emitReps(12);
    await flush();
    expect(cues().where((c) => c['text'] == 'Two more left.'), hasLength(1));
    expect(cues().where((c) => c['text'] == 'Good job.'), hasLength(1));
    expect(cues().last['text'], isNull);
  });

  test('Mute suppresses all cues; old spoken-count preference is ignored',
      () async {
    await audio.setPreferences(mode: WorkoutAudioMode.muted);
    final count = cues().length;
    tracker.completeCalibration();
    tracker.emitReps(5);
    await flush();
    expect(cues(), hasLength(count));
    await audio.setPreferences(mode: WorkoutAudioMode.voice);
    tracker.emitReps(6);
    await flush();
    expect(cues().last['tone'], 'rep');
    expect(cues().last['text'], isNull);
    await audio.setPreferences(mode: WorkoutAudioMode.tones);
    tracker.emitReps(8);
    await flush();
    expect(cues().last['mode'], 'tones');
    expect(cues().last['tone'], 'rep');
  });

  test('Reconnect snapshots do not play missed rep or target cues', () async {
    tracker.completeCalibration();
    tracker.emitReps(7);
    tracker.restoredOnConnect = TrackerStatus(
        state: TrackerState.running,
        repetitions: 10,
        calibrationReps: 3,
        bootId: tracker.bootId,
        sessionId: tracker.sessionId);
    tracker.emitStatus(null);
    await flush();
    final repSounds = cues().where((c) => c['tone'] == 'rep').length;
    await vm.reconnectActiveExercise(automatic: true);
    await flush();
    expect(cues().where((c) => c['tone'] == 'rep'), hasLength(repSounds));
    tracker.emitReps(11);
    await flush();
    expect(cues().last['text'], isNull);
    expect(cues().where((c) => c['text'] == 'Good job.'), isEmpty);
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
    await flush();
    expect(cues(), hasLength(count));
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
    expect(cues().last['text'], 'Calibration reset. Get ready.');
    expect(vm.liveReps, 0);
  });
}

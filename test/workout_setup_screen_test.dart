import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repform_app/app/app_services.dart';
import 'package:repform_app/features/auth/data/mock_auth_repository.dart';
import 'package:repform_app/features/auth/presentation/auth_view_model.dart';
import 'package:repform_app/features/tracker/data/tracker_gateway.dart';
import 'package:repform_app/features/tracker/domain/tracker_device.dart';
import 'package:repform_app/features/tracker/domain/tracker_status.dart';
import 'package:repform_app/features/workouts/data/workout_repository.dart';
import 'package:repform_app/features/workouts/domain/workout_models.dart';
import 'package:repform_app/features/workouts/presentation/calibration_screen.dart';
import 'package:repform_app/features/workouts/presentation/exercise_complete_screen.dart';
import 'package:repform_app/features/workouts/presentation/exercise_setup_screen.dart';
import 'package:repform_app/features/workouts/presentation/live_exercise_screen.dart';
import 'package:repform_app/features/workouts/presentation/workout_view_model.dart';

/// Tests drive explicit sensor reports; elapsed time never synthesizes repetitions.
class _UiTracker implements TrackerGateway {
  final _statuses = StreamController<TrackerStatus?>.broadcast(sync: true);
  final _counts = StreamController<int>.broadcast(sync: true);
  TrackerDevice? _device;
  TrackerStatus? _status;
  bool profileExists = false;
  bool emptyScan = false;
  int beginCalls = 0;
  int stopCalls = 0;
  int selectCalls = 0;

  @override
  TrackerDevice? get connectedDevice => _device;
  @override
  TrackerStatus? get status => _status;
  @override
  Stream<TrackerStatus?> get statuses => _statuses.stream;
  @override
  Stream<int> get repetitionCounts => _counts.stream;

  void report(TrackerState state, {int calibrationReps = 0, int reps = 0}) {
    _status = TrackerStatus(
        state: state,
        exerciseId: 1,
        sensorReady: true,
        profileAvailable: profileExists,
        repetitions: reps,
        calibrationReps: calibrationReps);
    _statuses.add(_status);
    if (state == TrackerState.running) _counts.add(reps);
  }

  @override
  Future<List<TrackerDevice>> scan() async =>
      emptyScan ? [] : const [TrackerDevice(id: 'AA:01', name: 'My tracker')];
  @override
  Future<void> connect(TrackerDevice device) async {
    _device = device;
  }

  @override
  Future<void> selectExercise({required String exerciseKind}) async {
    selectCalls++;
    report(profileExists ? TrackerState.ready : TrackerState.selected);
  }

  @override
  Future<void> beginCalibration({required String exerciseKind}) async {
    beginCalls++;
    profileExists = false;
    report(TrackerState.calibrating);
  }

  @override
  Future<void> refreshStatus() async {
    _statuses.add(_status);
  }

  @override
  Future<void> startCounting({required String exerciseKind}) async {
    report(TrackerState.running);
  }

  @override
  Future<void> pauseCounting() async {
    report(TrackerState.paused, reps: _status!.repetitions);
  }

  @override
  Future<void> resumeCounting() async {
    report(TrackerState.running, reps: _status!.repetitions);
  }

  @override
  Future<void> stopCounting() async {
    stopCalls++;
    report(profileExists ? TrackerState.ready : TrackerState.selected,
        reps: _status?.repetitions ?? 0);
  }

  @override
  Future<void> disconnect() async {
    _device = null;
    _status = null;
    _statuses.add(null);
  }

  @override
  Future<void> dispose() async {
    await _statuses.close();
    await _counts.close();
  }
}

class _UiRepository implements WorkoutRepository {
  _UiRepository(this.plan);
  final WorkoutPlan plan;
  final saved = <String, ExerciseResult>{};
  @override
  Future<List<WorkoutPlan>> fetchWorkouts() async => [plan];
  @override
  Future<Map<String, ExerciseResult>> fetchResults() async => Map.of(saved);
  @override
  Future<void> saveResult(ExerciseResult result) async {
    saved[result.key] = result;
  }
}

class _Flow {
  static const exercise = ExercisePlan(
      id: 'curl',
      name: 'Dumbbell Curl',
      kind: 'curl',
      targetReps: 5,
      coachTip: 'Control your movement.');
  final plan = WorkoutPlan(
      id: 'today',
      title: 'Today',
      description: '',
      scheduledAt: DateTime.now(),
      exercises: const [exercise]);
  final tracker = _UiTracker();
  final auth = AuthViewModel(MockAuthRepository());
  late final _UiRepository repository;
  late final WorkoutViewModel vm;

  Future<void> open(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 1000));
    repository = _UiRepository(plan);
    vm = WorkoutViewModel(repository: repository, tracker: tracker);
    await vm.load();
    await tester.pumpWidget(AppServices(
        auth: auth,
        workouts: vm,
        child: MaterialApp(
            home: ExerciseSetupScreen(workout: plan, exercise: exercise))));
    await tester.pumpAndSettle();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      vm.dispose();
      auth.dispose();
      await tester.binding.setSurfaceSize(null);
    });
  }

  Future<void> connect(WidgetTester tester) async {
    await tester.tap(find.text('Scan for devices'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('My tracker'));
    await tester.pumpAndSettle();
  }
}

void main() {
  testWidgets(
      'Device selection, real calibration progress and saved reps complete the flow',
      (tester) async {
    final flow = _Flow();
    await flow.open(tester);
    await flow.connect(tester);
    expect(flow.tracker.selectCalls, 1);
    expect(find.textContaining('null%'), findsNothing);
    final start = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, 'Start Exercise'));
    expect(start.onPressed, isNull);

    await tester.tap(find.text('Calibrate now'));
    await tester.pumpAndSettle();
    expect(find.byType(CalibrationScreen), findsOneWidget);
    expect(find.text('Record reference rep'), findsNothing);
    await tester.tap(find.text('Begin calibration'));
    await tester.pumpAndSettle();
    expect(flow.tracker.beginCalls, 1);
    expect(find.text('0 / 3'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    expect(find.text('0 / 3'), findsOneWidget);

    flow.tracker.report(TrackerState.calibrating, calibrationReps: 1);
    await tester.pumpAndSettle();
    expect(find.text('1 / 3'), findsOneWidget);
    flow.tracker.profileExists = true;
    flow.tracker.report(TrackerState.ready, calibrationReps: 3);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.byType(ExerciseSetupScreen), findsOneWidget);
    await tester.tap(find.text('Start Exercise'));
    await tester.pumpAndSettle();
    expect(find.byType(LiveExerciseScreen), findsOneWidget);

    flow.tracker.report(TrackerState.running, reps: 7);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Finish Exercise'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(find.byType(ExerciseCompleteScreen), findsOneWidget);
    expect(flow.repository.saved.values.single.repetitions, 7);
  });

  testWidgets('Leaving active calibration cancels it before returning to setup',
      (tester) async {
    final flow = _Flow();
    await flow.open(tester);
    await flow.connect(tester);
    await tester.tap(find.text('Calibrate now'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Begin calibration'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Cancel calibration?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Cancel calibration'));
    await tester.pumpAndSettle();
    expect(flow.tracker.stopCalls, 1);
    expect(find.byType(ExerciseSetupScreen), findsOneWidget);
    expect(flow.vm.canStartExercise(_Flow.exercise), isFalse);
  });

  testWidgets('An empty scan offers another scan and never invents devices',
      (tester) async {
    final flow = _Flow();
    flow.tracker.emptyScan = true;
    await flow.open(tester);
    await tester.tap(find.text('Scan for devices'));
    await tester.pumpAndSettle();
    expect(
        find.textContaining('No compatible trackers found.'), findsOneWidget);
    expect(find.text('Scan again'), findsOneWidget);
    expect(find.text('My tracker'), findsNothing);
  });
}

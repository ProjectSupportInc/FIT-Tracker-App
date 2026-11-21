import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repform_app/app/app_services.dart';
import 'package:repform_app/app/fittracker_theme.dart';
import 'package:repform_app/features/auth/data/mock_auth_repository.dart';
import 'package:repform_app/features/auth/presentation/auth_view_model.dart';
import 'package:repform_app/features/tracker/domain/tracker_device.dart';
import 'package:repform_app/features/tracker/domain/tracker_status.dart';
import 'package:repform_app/features/workouts/data/workout_repository.dart';
import 'package:repform_app/features/workouts/domain/workout_models.dart';
import 'package:repform_app/features/workouts/presentation/exercise_complete_screen.dart';
import 'package:repform_app/features/workouts/presentation/exercise_setup_screen.dart';
import 'package:repform_app/features/workouts/presentation/live_exercise_screen.dart';
import 'package:repform_app/features/workouts/presentation/workout_view_model.dart';

import 'workout_view_model_test.dart' show TestTracker;

class _UiTracker extends TestTracker {
  bool emptyScan = false;
  int scanCalls = 0;
  @override
  Future<List<TrackerDevice>> scan() async {
    scanCalls++;
    return emptyScan
        ? []
        : const [TrackerDevice(id: 'AA:01', name: 'My tracker')];
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

  Future<void> open(WidgetTester tester,
      {Size size = const Size(430, 1000), double textScale = 1}) async {
    await tester.binding.setSurfaceSize(size);
    repository = _UiRepository(plan);
    vm = WorkoutViewModel(repository: repository, tracker: tracker);
    await vm.load();
    await tester.pumpWidget(AppServices(
        auth: auth,
        workouts: vm,
        child: MaterialApp(
            theme: fitTheme(Brightness.dark),
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                    disableAnimations: true,
                    textScaler: TextScaler.linear(textScale)),
                child: child!),
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
    await tester.ensureVisible(find.text('My tracker'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('My tracker'));
    await tester.pumpAndSettle();
  }
}

void main() {
  testWidgets(
      'Scan, START, preparation, calibration and reps complete one session',
      (tester) async {
    final flow = _Flow();
    await flow.open(tester);
    await flow.connect(tester);
    expect(find.textContaining('null%'), findsNothing);
    await tester.ensureVisible(find.text('Start Exercise'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start Exercise'));
    await tester.pumpAndSettle();
    expect(find.byType(LiveExerciseScreen), findsOneWidget);
    expect(flow.tracker.startCalls, 1);
    expect(find.text('Lift into position'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    expect(flow.vm.liveReps, 0);

    flow.tracker.publish(TrackerState.settling);
    await tester.pumpAndSettle();
    expect(find.text('Hold still'), findsOneWidget);
    flow.tracker.publish(TrackerState.calibrating, calReps: 1);
    await tester.pumpAndSettle();
    expect(find.text('1 of 3 reps learned'), findsOneWidget);
    flow.tracker.completeCalibration();
    await tester.pumpAndSettle();
    expect(flow.vm.liveReps, 3);
    expect(find.text('Movement learned'), findsOneWidget);
    expect(flow.tracker.startCalls, 1);

    flow.tracker.emitReps(7);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Finish Exercise'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Finish Exercise'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(find.byType(ExerciseCompleteScreen), findsOneWidget);
    expect(flow.repository.saved.values.single.repetitions, 7);
  });

  testWidgets('Back during preparation confirms before stopping the device',
      (tester) async {
    final flow = _Flow();
    await flow.open(tester);
    await flow.connect(tester);
    await tester.ensureVisible(find.text('Start Exercise'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start Exercise'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Stop this exercise?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Stop exercise'));
    await tester.pumpAndSettle();
    expect(flow.tracker.stopCalls, 1);
    expect(flow.vm.hasActiveSession, isFalse);
    expect(flow.repository.saved, isEmpty);
  });

  testWidgets('An empty scan offers another scan and never invents devices',
      (tester) async {
    final flow = _Flow();
    flow.tracker.emptyScan = true;
    await flow.open(tester);
    expect(flow.tracker.scanCalls, 1);
    expect(
        find.textContaining('No compatible trackers found.'), findsOneWidget);
    expect(find.text('Scan again'), findsOneWidget);
    expect(find.text('My tracker'), findsNothing);
  });
  testWidgets(
      'Setup scans on entry and advances after connection, without starting the device',
      (tester) async {
    final flow = _Flow();
    await flow.open(tester);
    expect(flow.tracker.scanCalls, 1);
    expect(find.text('Connect your tracker'), findsOneWidget);
    expect(find.text('1. Connect Your Device'), findsNothing);
    await flow.connect(tester);
    expect(find.text('You’re connected'), findsOneWidget);
    expect(find.text('Connect your tracker'), findsNothing);
    expect(flow.tracker.startCalls, 0);
  });

  testWidgets('Setup and preparation scroll on a small screen with large text',
      (tester) async {
    final flow = _Flow();
    await flow.open(tester, size: const Size(320, 600), textScale: 1.6);
    expect(tester.takeException(), isNull);
    await flow.connect(tester);
    await tester.ensureVisible(find.text('Start Exercise'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start Exercise'));
    await tester.pumpAndSettle();
    expect(find.text('Lift into position'), findsOneWidget);
    expect(tester.takeException(), isNull);
    flow.tracker.publish(TrackerState.calibrating, calReps: 2);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Stop without completing'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

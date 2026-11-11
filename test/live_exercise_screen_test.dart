import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repform_app/app/app_services.dart';
import 'package:repform_app/features/auth/data/mock_auth_repository.dart';
import 'package:repform_app/features/auth/presentation/auth_view_model.dart';
import 'package:repform_app/features/workouts/domain/workout_models.dart';
import 'package:repform_app/features/workouts/presentation/exercise_complete_screen.dart';
import 'package:repform_app/features/workouts/presentation/live_exercise_screen.dart';
import 'package:repform_app/features/workouts/presentation/workout_view_model.dart';

import 'workout_view_model_test.dart' show TestRepository, TestTracker;

/// Lets tests hold a save in progress or reject it, like an unavailable backend.
class _Repository extends TestRepository {
  _Repository(super.plan);
  bool failSave = false;
  Completer<void>? pendingSave;

  @override
  Future<void> saveResult(ExerciseResult result) async {
    await pendingSave?.future;
    if (failSave) throw StateError('Storage unavailable');
    await super.saveResult(result);
  }
}

/// Mounts a real live screen above a home route with controlled tracker events.
class _Session {
  final tracker = TestTracker();
  final auth = AuthViewModel(MockAuthRepository());
  final navigator = GlobalKey<NavigatorState>();
  late final _Repository repository;
  late final WorkoutViewModel vm;
  static const exercise = ExercisePlan(
    id: 'curl',
    name: 'Curl',
    kind: 'curl',
    targetReps: 5,
    coachTip: '',
  );
  final plan = WorkoutPlan(
    id: 'today',
    title: 'Today',
    description: '',
    scheduledAt: DateTime.now(),
    exercises: const [exercise],
  );

  Future<void> open(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(400, 850));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    repository = _Repository(plan);
    vm = WorkoutViewModel(repository: repository, tracker: tracker);
    await vm.load();
    await vm.connect((await tracker.scan()).first);
    await vm.prepareExercise(exercise);
    await vm.beginCalibration(exercise);
    tracker.completeCalibration();
    await vm.startExercise(plan, exercise);
    await tester.pumpWidget(AppServices(
      auth: auth,
      workouts: vm,
      child: MaterialApp(
        navigatorKey: navigator,
        home: const Scaffold(body: Text('Workout details')),
      ),
    ));
    unawaited(navigator.currentState!.push(MaterialPageRoute<void>(
      builder: (_) => LiveExerciseScreen(workout: plan, exercise: exercise),
    )));
    await tester.pumpAndSettle();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      vm.dispose();
      auth.dispose();
    });
  }
}

/// Stream cancellation can complete in the real async zone; flush it before
/// checking navigation, then finish the route animation in the widget test clock.
Future<void> _settleCleanup(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(Duration.zero));
  await tester.pumpAndSettle();
}

/// Flutter's test runner invokes main() to register these interaction checks.
void main() {
  testWidgets('Short screens scroll to the stop action without overflow',
      (tester) async {
    final session = _Session();
    await session.open(tester);
    await tester.binding.setSurfaceSize(const Size(400, 500));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('Stop without completing'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stop without completing'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('Keep training'));
    await tester.pumpAndSettle();
    expect(session.vm.isRunning, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'System back confirms; cancel keeps counting; confirm stops without saving',
      (tester) async {
    final session = _Session();
    await session.open(tester);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.text('Stop this exercise?'), findsOneWidget);
    await tester.tap(find.text('Keep training'));
    await tester.pumpAndSettle();
    expect(find.byType(LiveExerciseScreen), findsOneWidget);
    expect(session.vm.isRunning, isTrue);
    expect(session.tracker.stopCalls, 0);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stop exercise'));
    await _settleCleanup(tester);
    expect(find.text('Workout details'), findsOneWidget);
    expect(find.byType(LiveExerciseScreen), findsNothing);
    expect(session.tracker.stopCalls, 1);
    expect(session.vm.isRunning, isFalse);
    expect(session.repository.results, isEmpty);
  });

  testWidgets(
      'Repeated stop requests show one dialog and close only after confirmation',
      (tester) async {
    final session = _Session();
    await session.open(tester);
    final close = tester
        .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.close))
        .onPressed!;
    close();
    // Simulate a second callback arriving before the disabled button rebuilds.
    close();
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    await tester.tap(find.text('Stop exercise'));
    await _settleCleanup(tester);
    expect(session.tracker.stopCalls, 1);
    expect(find.text('Workout details'), findsOneWidget);
  });

  testWidgets(
      'Finish saves overflow reps and replaces live with completion without a stop dialog',
      (tester) async {
    final session = _Session();
    await session.open(tester);
    session.tracker.emitReps(8);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Finish Exercise'));
    await _settleCleanup(tester);
    await tester.pumpAndSettle();
    expect(find.byType(ExerciseCompleteScreen), findsOneWidget);
    expect(find.byType(LiveExerciseScreen), findsNothing);
    expect(find.byType(AlertDialog), findsNothing);
    expect(session.repository.results.values.single.repetitions, 8);
    expect(session.tracker.stopCalls, 1);
  });

  testWidgets(
      'Back is ignored during saving; save failure shows a SnackBar and allows retry',
      (tester) async {
    final session = _Session();
    await session.open(tester);
    session.repository.failSave = true;
    session.repository.pendingSave = Completer<void>();
    session.tracker.emitReps(5);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Finish Exercise'));
    await tester.pump();
    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(AlertDialog), findsNothing);
    expect(session.tracker.stopCalls, 1);

    session.repository.pendingSave!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Unable to save this exercise. Please try again.'),
        findsOneWidget);
    expect(find.byType(LiveExerciseScreen), findsOneWidget);
    expect(session.vm.isRunning, isFalse);
    expect(session.vm.hasPendingResult, isTrue);
    expect(session.repository.results, isEmpty);

    session.repository.failSave = false;
    await tester.ensureVisible(find.text('Retry saving'));
    await tester.tap(find.text('Retry saving'));
    await _settleCleanup(tester);
    await tester.pumpAndSettle();
    expect(find.byType(ExerciseCompleteScreen), findsOneWidget);
    expect(session.repository.results, hasLength(1));
  });

  testWidgets('Stop failure keeps the live route and permits retry',
      (tester) async {
    final session = _Session();
    await session.open(tester);
    session.tracker.failStop = true;
    await tester.tap(find.text('Stop without completing'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stop exercise'));
    await _settleCleanup(tester);
    expect(find.text('Unable to stop this exercise. Please try again.'),
        findsOneWidget);
    expect(find.byType(LiveExerciseScreen), findsOneWidget);
    expect(session.vm.isRunning, isTrue);
    session.tracker.failStop = false;
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Stop exercise'));
    await _settleCleanup(tester);
    expect(find.text('Workout details'), findsOneWidget);
    expect(session.repository.results, isEmpty);
  });
}

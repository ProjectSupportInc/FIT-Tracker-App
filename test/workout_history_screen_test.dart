import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repform_app/app/app_services.dart';
import 'package:repform_app/app/fittracker_theme.dart';
import 'package:repform_app/features/auth/data/mock_auth_repository.dart';
import 'package:repform_app/features/auth/presentation/auth_view_model.dart';
import 'package:repform_app/features/workouts/domain/workout_models.dart';
import 'package:repform_app/features/workouts/presentation/exercise_setup_screen.dart';
import 'package:repform_app/features/workouts/presentation/workout_detail_screen.dart';
import 'package:repform_app/features/workouts/presentation/workout_history_screen.dart';
import 'package:repform_app/features/workouts/presentation/workout_view_model.dart';
import 'workout_view_model_test.dart' show TestRepository, TestTracker;

void main() {
  testWidgets(
      'Completed exercise opens results; repeat is confirmed from its options menu',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    const exercise = ExercisePlan(
        id: 'curl', name: 'Curl', kind: 'curl', targetReps: 5, coachTip: '');
    final plan = WorkoutPlan(
        id: 'today',
        title: 'Today',
        description: '',
        scheduledAt: DateTime.now(),
        exercises: const [exercise]);
    final repository = TestRepository(plan);
    final result = ExerciseResult(
        workoutId: plan.id,
        exerciseId: exercise.id,
        repetitions: 6,
        deviceId: 'tracker',
        completedAt: DateTime.now());
    repository.results[result.key] = result;
    final tracker = TestTracker();
    final vm = WorkoutViewModel(repository: repository, tracker: tracker);
    final auth = AuthViewModel(MockAuthRepository());
    await vm.load();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      vm.dispose();
      auth.dispose();
      await tester.binding.setSurfaceSize(null);
    });
    await tester.pumpWidget(AppServices(
        auth: auth,
        workouts: vm,
        child: MaterialApp(
            theme: fitTheme(Brightness.dark),
            home: WorkoutDetailScreen(workout: plan))));
    await tester.tap(find.text('Curl'));
    await tester.pumpAndSettle();
    expect(find.byType(WorkoutHistoryScreen), findsOneWidget);
    expect(find.text('6 reps'), findsOneWidget);
    await tester.tap(find.byTooltip('Result options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Repeat exercise'));
    await tester.pumpAndSettle();
    expect(vm.repeat, isNull);
    expect(find.text('Start new attempt'), findsOneWidget);
    await tester.tap(find.text('Keep current results'));
    await tester.pumpAndSettle();
    expect(vm.repeat, isNull);
    await tester.tap(find.byTooltip('Result options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Repeat exercise'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Start new attempt'));
    await tester.pumpAndSettle();
    expect(find.byType(ExerciseSetupScreen), findsOneWidget);
    expect(vm.repeat!.exerciseId, exercise.id);
    expect(vm.exerciseComplete(plan, exercise), isTrue);
    expect(tracker.startCalls, 0);
    expect(tester.takeException(), isNull);
  });
}

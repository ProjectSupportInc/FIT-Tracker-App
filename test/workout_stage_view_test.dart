import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:repform_app/app/fittracker_theme.dart';
import 'package:repform_app/features/tracker/domain/tracker_status.dart';
import 'package:repform_app/features/workouts/presentation/workout_stage_view.dart';

Future<void> showStage(
  WidgetTester tester,
  TrackerState state, {
  int reps = 0,
  int learned = 0,
  bool disconnected = false,
  bool reduceMotion = false,
  bool animate = true,
  bool tickerEnabled = true,
  double textScale = 1,
  Brightness brightness = Brightness.dark,
}) async {
  await tester.pumpWidget(MaterialApp(
    theme: fitTheme(brightness),
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        disableAnimations: reduceMotion,
        textScaler: TextScaler.linear(textScale),
      ),
      child: TickerMode(enabled: tickerEnabled, child: child!),
    ),
    home: Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: WorkoutStageView(
          status: TrackerStatus(state: state, calibrationReps: learned),
          repetitions: reps,
          target: 10,
          disconnected: disconnected,
          animate: animate,
        ),
      ),
    ),
  ));
}

double cuePosition(WidgetTester tester) => tester
    .widget<Transform>(find.byKey(const ValueKey('movement-cue')))
    .transform
    .getTranslation()
    .y;

void main() {
  testWidgets('Pickup moves without advancing the device phase or count',
      (tester) async {
    await showStage(tester, TrackerState.waitPickup);
    final first = cuePosition(tester);
    await tester.pump(const Duration(milliseconds: 600));
    expect(cuePosition(tester), isNot(closeTo(first, 0.01)));
    await tester.pump(const Duration(seconds: 20));
    expect(find.text('Take your starting position'), findsOneWidget);
    expect(find.text('Hold this position'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await showStage(tester, TrackerState.settling);
    await tester.pump(const Duration(seconds: 1));
    expect(cuePosition(tester), 0);
    expect(find.text('Hold this position'), findsOneWidget);
    expect(find.byIcon(Icons.pan_tool_outlined), findsOneWidget);
  });

  testWidgets('Calibration checkpoints follow received reps, including reset',
      (tester) async {
    await showStage(tester, TrackerState.calibrating);
    await tester.pump(const Duration(seconds: 10));
    expect(find.text('0 of 3 reps recorded'), findsOneWidget);
    expect(find.byIcon(Icons.check_circle_rounded), findsNothing);

    for (final learned in [1, 2, 0, 1, 2, 3]) {
      await showStage(tester, TrackerState.calibrating, learned: learned);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('$learned of 3 reps recorded'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_rounded), findsNWidgets(learned));
    }
    await tester.pump(const Duration(seconds: 10));
    expect(find.text('Rep 3 recorded'), findsOneWidget);
    expect(find.text('Ready. Keep going.'), findsNothing);

    await showStage(tester, TrackerState.running, reps: 3, learned: 3);
    await tester.pumpAndSettle();
    expect(find.text('Ready. Keep going.'), findsOneWidget);
    expect(find.byKey(const ValueKey('rep-3')), findsOneWidget);
    await tester.pump(const Duration(seconds: 20));
    expect(find.byKey(const ValueKey('rep-4')), findsNothing);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('Real count changes animate without inventing intermediate reps',
      (tester) async {
    await showStage(tester, TrackerState.running, reps: 4);
    await tester.pumpAndSettle();
    await showStage(tester, TrackerState.running, reps: 7);
    await tester.pump(const Duration(milliseconds: 50));
    final ring = tester.widget<CircularProgressIndicator>(
        find.byType(CircularProgressIndicator));
    expect(ring.value, allOf(greaterThan(0.4), lessThan(0.7)));
    expect(find.byKey(const ValueKey('rep-7')), findsOneWidget);
    expect(find.byKey(const ValueKey('rep-5')), findsNothing);
    expect(find.byKey(const ValueKey('rep-6')), findsNothing);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('rep-4')), findsNothing);
    expect(
        tester
            .widget<CircularProgressIndicator>(
                find.byType(CircularProgressIndicator))
            .value,
        0.7);

    await showStage(tester, TrackerState.running, reps: 12);
    await tester.pumpAndSettle();
    expect(find.text('Target reached'), findsOneWidget);
    expect(find.text('+2 extra reps'), findsOneWidget);
  });

  testWidgets('Preparation motion stops in the background and when hidden',
      (tester) async {
    await showStage(tester, TrackerState.waitPickup);
    await tester.pump(const Duration(milliseconds: 600));
    expect(tester.binding.hasScheduledFrame, isTrue);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
    final stopped = cuePosition(tester);
    await tester.pump(const Duration(seconds: 1));
    expect(cuePosition(tester), stopped);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));
    expect(cuePosition(tester), isNot(stopped));

    await showStage(tester, TrackerState.waitPickup, tickerEnabled: false);
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
    await showStage(tester, TrackerState.waitPickup, animate: false);
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('Reduced motion and paused or disconnected states stay still',
      (tester) async {
    await showStage(tester, TrackerState.calibrating, reduceMotion: true);
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
    final stopped = cuePosition(tester);
    await tester.pump(const Duration(seconds: 1));
    expect(cuePosition(tester), stopped);

    await showStage(tester, TrackerState.calibrating);
    await tester.pump(const Duration(milliseconds: 600));
    await showStage(tester, TrackerState.paused, reps: 5);
    await tester.pumpAndSettle();
    expect(find.text('Workout paused'), findsOneWidget);
    expect(find.byKey(const ValueKey('rep-5')), findsOneWidget);
    expect(tester.binding.hasScheduledFrame, isFalse);

    await showStage(tester, TrackerState.calibrating, disconnected: true);
    await tester.pumpAndSettle();
    expect(find.text('Connection lost'), findsOneWidget);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('Stages fit a narrow screen with large text in either theme',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final brightness in Brightness.values) {
      for (final state in TrackerState.values) {
        await showStage(tester, state,
            reps: state == TrackerState.running ? 65535 : 0,
            textScale: 2,
            reduceMotion: true,
            brightness: brightness);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull,
            reason: '$state in $brightness at 200% text size');
      }
    }
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:repform_app/app/fittracker_app.dart';
import 'package:repform_app/features/tracker/data/mock_tracker_gateway.dart';
import 'package:repform_app/features/workouts/data/demo_workout_repository.dart';

void main() {
  testWidgets('Sign in opens Today navigation', (tester) async {
    await tester.pumpWidget(FitTrackerApp(
        tracker: MockTrackerGateway(), repository: DemoWorkoutRepository()));
    expect(find.text('Continue with Google'), findsOneWidget);
    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle(const Duration(milliseconds: 500));
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Workouts'), findsWidgets);
  });
}

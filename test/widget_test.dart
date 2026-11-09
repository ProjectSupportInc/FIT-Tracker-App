import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../lib/app/fittracker_app.dart';

void main() {
  testWidgets('Sign in opens Today navigation', (tester) async {
    await tester.pumpWidget(const FitTrackerApp());
    expect(find.text('Continue with Google'), findsOneWidget);
    await tester.tap(find.text('Continue with Google'));
    await tester.pumpAndSettle(const Duration(milliseconds: 500));
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Workouts'), findsWidgets);
  });
}

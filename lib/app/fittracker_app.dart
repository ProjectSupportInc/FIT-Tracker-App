import 'package:flutter/material.dart';

import '../features/auth/data/mock_auth_repository.dart';
import '../features/auth/presentation/auth_view_model.dart';
import '../features/auth/presentation/sign_in_screen.dart';
import '../features/shell/presentation/main_shell.dart';
import '../features/tracker/data/mock_tracker_gateway.dart';
import '../features/workouts/data/demo_workout_repository.dart';
import '../features/workouts/presentation/workout_view_model.dart';
import 'app_services.dart';
import 'fittracker_theme.dart';

class FitTrackerApp extends StatefulWidget {
  const FitTrackerApp({super.key});

  @override
  State<FitTrackerApp> createState() => _FitTrackerAppState();
}

class _FitTrackerAppState extends State<FitTrackerApp> {
  late final AuthViewModel _auth;
  late final WorkoutViewModel _workouts;
  final ThemeViewModel _theme = ThemeViewModel();

  @override
  void initState() {
    super.initState();
    _auth = AuthViewModel(MockAuthRepository());
    _workouts = WorkoutViewModel(
      repository: DemoWorkoutRepository(),
      tracker: MockTrackerGateway(),
    );
    _workouts.load();
  }

  @override
  void dispose() {
    _auth.dispose();
    _workouts.dispose();
    _theme.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppServices(
      auth: _auth,
      workouts: _workouts,
      child: AnimatedBuilder(
        animation: _theme,
        builder: (context, _) => MaterialApp(
          title: 'FitTracker',
          debugShowCheckedModeBanner: false,
          theme: fitTheme(Brightness.light),
          darkTheme: fitTheme(Brightness.dark),
          themeMode: _theme.mode,
          home: AnimatedBuilder(
            animation: _auth,
            builder: (context, _) => _auth.isSignedIn
                ? MainShell(theme: _theme)
                : const SignInScreen(),
          ),
        ),
      ),
    );
  }
}

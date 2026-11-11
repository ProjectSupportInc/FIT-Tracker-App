// Creates real BLE/storage services once and owns their lifetime. Auth remains a demo.
// Read docs/BEGINNER_GUIDE.md for the app flow and Dart syntax explanations.
// Imported by:
// - lib/main.dart

import 'dart:async';

import 'package:flutter/material.dart';

import '../features/auth/data/mock_auth_repository.dart';
import '../features/auth/presentation/auth_view_model.dart';
import '../features/auth/presentation/sign_in_screen.dart';
import '../features/shell/presentation/main_shell.dart';
import '../features/tracker/data/ble_tracker_gateway.dart';
import '../features/tracker/data/tracker_gateway.dart';
import '../features/workouts/data/local_workout_repository.dart';
import '../features/workouts/data/workout_repository.dart';
import '../features/workouts/presentation/workout_view_model.dart';
import 'app_services.dart';
import 'fittracker_theme.dart';

/// Root widget created in main.dart; its State owns the controllers for this app session.
class FitTrackerApp extends StatefulWidget {
  /// Creates FitTrackerApp; required arguments supply its dependencies or display data.
  const FitTrackerApp({super.key, this.tracker, this.repository});

  /// Tests may inject adapters; normal launches always use real BLE and storage.
  final TrackerGateway? tracker;
  final WorkoutRepository? repository;

  /// Flutter calls this when inserting the widget; returns the object that holds its mutable state.
  @override
  State<FitTrackerApp> createState() => _FitTrackerAppState();
}

/// Mutable state for FitTrackerApp. Flutter creates it through createState().
class _FitTrackerAppState extends State<FitTrackerApp>
    with WidgetsBindingObserver {
  /// Authentication controller owned and disposed by the root app State.
  late final AuthViewModel _auth;

  /// Workout controller owned and disposed by the root app State.
  late final WorkoutViewModel _workouts;

  /// Theme controller owned by the app; listened to by its AnimatedBuilder.
  final ThemeViewModel _theme = ThemeViewModel();

  /// Flutter calls this once when State is attached; creates and loads this app’s shared controllers.
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _auth = AuthViewModel(MockAuthRepository());
    _workouts = WorkoutViewModel(
      repository: widget.repository ?? LocalWorkoutRepository(),
      tracker: widget.tracker ?? BleTrackerGateway(),
    );
    _workouts.load();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Permission dialogs only make the app inactive; pause on actual backgrounding.
    if (state == AppLifecycleState.paused) {
      unawaited(_workouts.pauseForBackground().catchError((Object _) {}));
    }
  }

  /// Releases subscriptions/timers/controllers when the owner is removed; prevents work after cleanup.
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _auth.dispose();
    _workouts.dispose();
    _theme.dispose();
    super.dispose();
  }

  /// Flutter calls this to describe the UI. context locates services/theme/navigation above this widget.
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

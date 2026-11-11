// Makes the shared authentication and workout controllers accessible to descendant widgets.
// Read docs/BEGINNER_GUIDE.md for the app flow and Dart syntax explanations.
// Imported by:
// - lib/app/fittracker_app.dart
// - lib/features/auth/presentation/sign_in_screen.dart
// - lib/features/home/presentation/today_screen.dart
// - lib/features/profile/presentation/profile_screen.dart
// - lib/features/progress/presentation/progress_screen.dart
// - lib/features/workouts/presentation/calibration_screen.dart
// - lib/features/workouts/presentation/exercise_complete_screen.dart
// - lib/features/workouts/presentation/exercise_setup_screen.dart
// - lib/features/workouts/presentation/live_exercise_screen.dart
// - lib/features/workouts/presentation/workout_detail_screen.dart
// - lib/features/workouts/presentation/workouts_screen.dart

import 'package:flutter/widgets.dart';

import '../features/auth/presentation/auth_view_model.dart';
import '../features/workouts/presentation/workout_view_model.dart';

/// Dependency injection boundary for UI features.
/// Shared service container. Screens use AppServices.of(context) to find the same controllers.
class AppServices extends InheritedWidget {
  /// Creates AppServices; required arguments supply its dependencies or display data.
  const AppServices({
    super.key,
    required this.auth,
    required this.workouts,
    required super.child,
  });

  /// Shared authentication controller used for user data and sign-in/sign-out actions.
  final AuthViewModel auth;

  /// Shared workout controller found by screens through AppServices.of(context).
  final WorkoutViewModel workouts;

  /// Finds the nearest AppServices ancestor using context; called by screens to access shared controllers.
  static AppServices of(BuildContext context) {
    // Nearest AppServices widget found in the ancestor tree; returned to the requesting screen.
    final services = context.dependOnInheritedWidgetOfExactType<AppServices>();
    assert(services != null, 'AppServices not found above this widget');
    return services!;
  }

  /// Flutter calls this when AppServices is replaced; dependents rebuild if controller identities change.
  @override
  bool updateShouldNotify(AppServices oldWidget) =>
      auth != oldWidget.auth || workouts != oldWidget.workouts;
}

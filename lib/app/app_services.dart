import 'package:flutter/widgets.dart';

import '../features/auth/presentation/auth_view_model.dart';
import '../features/workouts/presentation/workout_view_model.dart';

/// Dependency injection boundary for UI features.
class AppServices extends InheritedWidget {
  const AppServices({
    super.key,
    required this.auth,
    required this.workouts,
    required super.child,
  });

  final AuthViewModel auth;
  final WorkoutViewModel workouts;

  static AppServices of(BuildContext context) {
    final services = context.dependOnInheritedWidgetOfExactType<AppServices>();
    assert(services != null, 'AppServices not found above this widget');
    return services!;
  }

  @override
  bool updateShouldNotify(AppServices oldWidget) =>
      auth != oldWidget.auth || workouts != oldWidget.workouts;
}

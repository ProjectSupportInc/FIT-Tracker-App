// Defines shared colors, light/dark theme settings, and the controller for switching themes.
// Read docs/BEGINNER_GUIDE.md for the app flow and Dart syntax explanations.
// Imported by:
// - lib/app/fittracker_app.dart
// - lib/core/widgets/fit_widgets.dart
// - lib/features/auth/presentation/sign_in_screen.dart
// - lib/features/home/presentation/today_screen.dart
// - lib/features/meals/presentation/meals_screen.dart
// - lib/features/profile/presentation/profile_screen.dart
// - lib/features/progress/presentation/progress_screen.dart
// - lib/features/shell/presentation/main_shell.dart
// - lib/features/workouts/presentation/calibration_screen.dart
// - lib/features/workouts/presentation/exercise_complete_screen.dart
// - lib/features/workouts/presentation/exercise_setup_screen.dart
// - lib/features/workouts/presentation/live_exercise_screen.dart
// - lib/features/workouts/presentation/workout_card.dart
// - lib/features/workouts/presentation/workout_detail_screen.dart

import 'package:flutter/material.dart';

/// Named color constants reused by fitTheme() and presentation widgets.
class FitColors {
  /// Bright accent used for primary buttons, badges, and progress indicators.
  static const lime = Color(0xFFB8FF4D);

  /// Dark-mode page background.
  static const navy = Color(0xFF091C20);

  /// Dark-mode card/surface background.
  static const navyCard = Color(0xFF132A2E);

  /// Dark text/icon color, especially on the lime accent.
  static const ink = Color(0xFF14292C);

  /// Pale background used for light-mode badges and navigation selection.
  static const softGreen = Color(0xFFE8F0ED);

  /// Secondary accent used for selected icons and small headings.
  static const peach = Color(0xFFF2A16C);
}

/// Theme state created by FitTrackerApp and passed through MainShell to ProfileScreen.
class ThemeViewModel extends ChangeNotifier {
  /// Current theme selection; toggle() updates it and notifies listeners.
  ThemeMode _mode = ThemeMode.dark;

  /// Read-only theme selection consumed by MaterialApp.themeMode.
  ThemeMode get mode => _mode;

  /// Whether dark mode is selected; ProfileScreen uses it for the switch value.
  bool get isDark => _mode == ThemeMode.dark;

  /// Switches light/dark mode and notifies FitTrackerApp; called by the profile theme switch.
  void toggle() {
    _mode = isDark ? ThemeMode.light : ThemeMode.dark;
    notifyListeners();
  }
}

/// Builds the Material theme for the requested brightness; FitTrackerApp calls it for both themes.
ThemeData fitTheme(Brightness brightness) {
  /// Whether this widget/theme is using dark brightness; selects suitable colors.
  final dark = brightness == Brightness.dark;

  /// Page/app-bar background chosen for this brightness.
  final background = dark ? FitColors.navy : const Color(0xFFF4F8F7);

  /// Card and navigation surface color chosen for this brightness.
  final surface = dark ? FitColors.navyCard : Colors.white;

  /// Default readable text color chosen for this brightness.
  final foreground = dark ? const Color(0xFFF1FBF6) : FitColors.ink;

  /// Material color scheme passed into ThemeData.
  final scheme = ColorScheme.fromSeed(
    seedColor: FitColors.lime,
    brightness: brightness,
    primary: dark ? FitColors.lime : const Color(0xFF315B45),
    surface: surface,
    onSurface: foreground,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: background,
    appBarTheme: AppBarTheme(
      backgroundColor: background,
      foregroundColor: foreground,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: surface,
      indicatorColor: dark ? const Color(0xFF294A3B) : FitColors.softGreen,
      height: 78,
      labelTextStyle: WidgetStateProperty.all(
        const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: FitColors.lime,
        foregroundColor: FitColors.ink,
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontWeight: FontWeight.w800),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(50),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
  );
}

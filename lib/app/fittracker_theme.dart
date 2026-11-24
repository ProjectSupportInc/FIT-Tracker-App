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
// - lib/features/workouts/presentation/exercise_complete_screen.dart
// - lib/features/workouts/presentation/exercise_setup_screen.dart
// - lib/features/workouts/presentation/live_exercise_screen.dart
// - lib/features/workouts/presentation/workout_card.dart
// - lib/features/workouts/presentation/workout_detail_screen.dart

import 'package:flutter/material.dart';

/// Named color constants reused by fitTheme() and presentation widgets.
class FitColors {
  /// Bright accent used for selected dates, badges, and progress indicators.
  static const accent = Color(0xFF32D26F);

  /// Dark-mode page background.
  static const background = Color(0xFF000000);

  /// Dark-mode card/surface background.
  static const surface = Color(0xFF1E1E1E);

  /// Dark text/icon color, especially on the green accent.
  static const ink = Color(0xFF141414);

  /// Pale background used for light-mode badges and navigation selection.
  static const accentContainerLight = Color(0xFFE4F4E9);

  /// Secondary accent used for selected icons and small headings.
  static const amber = Color(0xFFFFB340);
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
  final background = dark ? FitColors.background : const Color(0xFFF5F5F5);

  /// Card and navigation surface color chosen for this brightness.
  final surface = dark ? FitColors.surface : Colors.white;

  /// Default readable text color chosen for this brightness.
  final foreground = dark ? const Color(0xFFF5F5F5) : FitColors.ink;

  /// Material color scheme passed into ThemeData.
  final scheme = ColorScheme.fromSeed(
    seedColor: FitColors.accent,
    brightness: brightness,
    primary: dark ? FitColors.accent : const Color(0xFF167A3E),
    surface: surface,
    onSurface: foreground,
    onPrimary: dark ? FitColors.ink : Colors.white,
    secondary: dark ? FitColors.amber : const Color(0xFF8C5000),
    onSurfaceVariant: dark ? const Color(0xFFB3B3B3) : const Color(0xFF595959),
    surfaceContainerHighest:
        dark ? const Color(0xFF2B2B2B) : const Color(0xFFE8E8E8),
    surfaceContainerHigh:
        dark ? const Color(0xFF262626) : const Color(0xFFF0F0F0),
    surfaceContainer: surface,
    surfaceContainerLow: surface,
    outline: const Color(0xFF767676),
    outlineVariant: dark ? const Color(0xFF383838) : const Color(0xFFD6D6D6),
  );

  // Larger reading sizes keep workout prompts legible at arm's length.
  final textTheme = ThemeData(brightness: brightness)
      .textTheme
      .copyWith(
        headlineMedium:
            const TextStyle(fontSize: 32, fontWeight: FontWeight.w800),
        headlineSmall:
            const TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
        titleLarge: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
        titleMedium: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
        bodyLarge: const TextStyle(fontSize: 18, height: 1.45),
        bodyMedium: const TextStyle(fontSize: 16, height: 1.4),
        bodySmall: const TextStyle(fontSize: 14, height: 1.4),
        labelLarge: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
      )
      .apply(bodyColor: foreground, displayColor: foreground);

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    textTheme: textTheme,
    scaffoldBackgroundColor: background,
    appBarTheme: AppBarTheme(
      backgroundColor: background,
      foregroundColor: foreground,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
          color: foreground, fontSize: 22, fontWeight: FontWeight.w700),
    ),
    cardTheme: CardThemeData(
      color: surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: surface,
      indicatorColor:
          dark ? const Color(0xFF303030) : FitColors.accentContainerLight,
      height: 78,
      labelTextStyle: WidgetStateProperty.all(
        const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: dark ? Colors.white : FitColors.ink,
        foregroundColor: dark ? FitColors.ink : Colors.white,
        minimumSize: const Size.fromHeight(56),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(54),
        textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
          textStyle:
              const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
    ),
  );
}

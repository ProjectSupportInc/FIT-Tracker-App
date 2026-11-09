import 'package:flutter/material.dart';

class FitColors {
  static const lime = Color(0xFFB8FF4D);
  static const navy = Color(0xFF091C20);
  static const navyCard = Color(0xFF132A2E);
  static const ink = Color(0xFF14292C);
  static const softGreen = Color(0xFFE8F0ED);
  static const peach = Color(0xFFF2A16C);
}

class ThemeViewModel extends ChangeNotifier {
  ThemeMode _mode = ThemeMode.dark;
  ThemeMode get mode => _mode;
  bool get isDark => _mode == ThemeMode.dark;

  void toggle() {
    _mode = isDark ? ThemeMode.light : ThemeMode.dark;
    notifyListeners();
  }
}

ThemeData fitTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final background = dark ? FitColors.navy : const Color(0xFFF4F8F7);
  final surface = dark ? FitColors.navyCard : Colors.white;
  final foreground = dark ? const Color(0xFFF1FBF6) : FitColors.ink;
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

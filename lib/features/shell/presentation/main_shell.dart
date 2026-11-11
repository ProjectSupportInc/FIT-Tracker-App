// Hosts the four main tabs and opens the profile/settings route.
// Read docs/BEGINNER_GUIDE.md for the app flow and Dart syntax explanations.
// Imported by:
// - lib/app/fittracker_app.dart

import 'package:flutter/material.dart';

import '../../../app/fittracker_theme.dart';
import '../../home/presentation/today_screen.dart';
import '../../meals/presentation/meals_screen.dart';
import '../../profile/presentation/profile_screen.dart';
import '../../progress/presentation/progress_screen.dart';
import '../../workouts/presentation/workouts_screen.dart';

/// Signed-in home created by FitTrackerApp; keeps tab widgets in an IndexedStack.
class MainShell extends StatefulWidget {
  /// Creates MainShell; required arguments supply its dependencies or display data.
  const MainShell({super.key, required this.theme});

  /// Theme controller passed from the root through MainShell into ProfileScreen.
  final ThemeViewModel theme;

  /// Flutter calls this when inserting the widget; returns the object that holds its mutable state.
  @override
  State<MainShell> createState() => _MainShellState();
}

/// Mutable state for MainShell. Flutter creates it through createState().
class _MainShellState extends State<MainShell> {
  /// Index of the active bottom-navigation tab.
  int _selected = 0;

  /// Tab widgets kept in an IndexedStack: Today, Workouts, Meals, and Progress.
  static const _pages = [
    TodayScreen(),
    WorkoutsScreen(),
    MealsScreen(),
    ProgressScreen()
  ];

  /// Flutter calls this to describe the UI. context locates services/theme/navigation above this widget.
  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Row(children: [
            Icon(Icons.north_east_rounded, color: FitColors.lime),
            SizedBox(width: 8),
            Text('FITTRACKER',
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1)),
          ]),
          actions: [
            IconButton(
              tooltip: 'Account and settings',
              onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                      builder: (_) => ProfileScreen(theme: widget.theme))),
              icon: const CircleAvatar(
                  radius: 17, child: Icon(Icons.person_outline, size: 19)),
            ),
            const SizedBox(width: 10),
          ],
        ),
        body: IndexedStack(index: _selected, children: _pages),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _selected,
          onDestinationSelected: (index) => setState(() => _selected = index),
          destinations: const [
            NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home),
                label: 'Today'),
            NavigationDestination(
                icon: Icon(Icons.fitness_center_outlined),
                selectedIcon: Icon(Icons.fitness_center),
                label: 'Workouts'),
            NavigationDestination(
                icon: Icon(Icons.restaurant_menu_outlined),
                selectedIcon: Icon(Icons.restaurant_menu),
                label: 'Meals'),
            NavigationDestination(
                icon: Icon(Icons.bar_chart_outlined),
                selectedIcon: Icon(Icons.bar_chart),
                label: 'Progress'),
          ],
        ),
      );
}

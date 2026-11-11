// Shows the nutrition placeholder; no meal data service exists yet.
// Read docs/BEGINNER_GUIDE.md for the app flow and Dart syntax explanations.
// Imported by:
// - lib/features/shell/presentation/main_shell.dart

import 'package:flutter/material.dart';

import '../../../app/fittracker_theme.dart';
import '../../../core/widgets/fit_widgets.dart';

/// Meals tab created in MainShell._pages; currently displays placeholder content.
class MealsScreen extends StatelessWidget {
  /// Creates MealsScreen; required arguments supply its dependencies or display data.
  const MealsScreen({super.key});

  /// Flutter calls this to describe the UI. context locates services/theme/navigation above this widget.
  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 28),
        children: [
          const SectionHeading('Fuel your progress.',
              subtitle: 'Nutrition plans that support your training.'),
          const SizedBox(height: 24),
          FitCard(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                const Icon(Icons.restaurant, size: 44, color: FitColors.lime),
                const SizedBox(height: 18),
                Text('Meal plans',
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                Text(
                    'Your coach\'s meal plan will appear here in a future release.',
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ])),
        ],
      );
}

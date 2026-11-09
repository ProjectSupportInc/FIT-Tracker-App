import 'package:flutter/material.dart';

import '../../../app/fittracker_theme.dart';
import '../../../core/widgets/fit_widgets.dart';

class MealsScreen extends StatelessWidget {
  const MealsScreen({super.key});

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.fromLTRB(22, 18, 22, 28),
        children: [
          const SectionHeading('Fuel your progress.',
            subtitle: 'Nutrition plans that support your training.'),
          const SizedBox(height: 24),
          FitCard(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Icon(Icons.restaurant, size: 44, color: FitColors.lime),
            const SizedBox(height: 18),
            Text('Meal plans', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900)),
            const SizedBox(height: 8),
            Text('Your coach\'s meal plan will appear here in a future release.',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ])),
        ],
      );
}

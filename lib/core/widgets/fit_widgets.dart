// Reusable visual components: cards, section headings, badges, buttons, and statistics.
// Read docs/BEGINNER_GUIDE.md for the app flow and Dart syntax explanations.
// Imported by:
// - lib/features/auth/presentation/sign_in_screen.dart
// - lib/features/home/presentation/today_screen.dart
// - lib/features/meals/presentation/meals_screen.dart
// - lib/features/profile/presentation/profile_screen.dart
// - lib/features/progress/presentation/progress_screen.dart
// - lib/features/workouts/presentation/calibration_screen.dart
// - lib/features/workouts/presentation/exercise_complete_screen.dart
// - lib/features/workouts/presentation/exercise_setup_screen.dart
// - lib/features/workouts/presentation/live_exercise_screen.dart
// - lib/features/workouts/presentation/workout_card.dart
// - lib/features/workouts/presentation/workout_detail_screen.dart
// - lib/features/workouts/presentation/workouts_screen.dart

import 'package:flutter/material.dart';

import '../../app/fittracker_theme.dart';

/// Reusable padded, optionally tappable card used across feature screens.
class FitCard extends StatelessWidget {
  /// Creates FitCard; required arguments supply its dependencies or display data.
  const FitCard(
      {super.key,
      required this.child,
      this.padding = const EdgeInsets.all(18),
      this.onTap});

  /// Content supplied by the parent widget and displayed inside this container.
  final Widget child;

  /// Space between the card edges and its content.
  final EdgeInsets padding;

  /// Optional card-tap callback supplied by the parent; null makes the card non-actionable.
  final VoidCallback? onTap;

  /// Flutter calls this to describe the UI. context locates services/theme/navigation above this widget.
  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      );
}

/// Title and optional subtitle used at the top of sections across feature screens.
class SectionHeading extends StatelessWidget {
  /// Creates SectionHeading; required arguments supply its dependencies or display data.
  const SectionHeading(this.title, {super.key, this.subtitle});

  /// Title displayed by this component or workout.
  final String title;

  /// Optional explanatory text displayed below a section title.
  final String? subtitle;

  /// Flutter calls this to describe the UI. context locates services/theme/navigation above this widget.
  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w900, letterSpacing: -0.8)),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(subtitle!,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ],
      );
}

/// Compact status label, optionally highlighted or accompanied by an icon.
class FitBadge extends StatelessWidget {
  /// Creates FitBadge; required arguments supply its dependencies or display data.
  const FitBadge(this.label, {super.key, this.highlight = false, this.icon});

  /// Text displayed on this badge/button/statistic or derived from workout availability.
  final String label;

  /// Whether the badge should use the bright accent background.
  final bool highlight;

  /// Optional or default icon displayed alongside the component’s text.
  final IconData? icon;

  /// Flutter calls this to describe the UI. context locates services/theme/navigation above this widget.
  @override
  Widget build(BuildContext context) {
    // Whether this widget/theme is using dark brightness; selects suitable colors.
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: highlight
            ? FitColors.lime
            : (dark ? const Color(0xFF254247) : FitColors.softGreen),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 13), const SizedBox(width: 5)],
        Text(label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: highlight ? FitColors.ink : null,
            )),
      ]),
    );
  }
}

/// Shared primary action button; a null onPressed disables it.
class AccentButton extends StatelessWidget {
  /// Creates AccentButton; required arguments supply its dependencies or display data.
  const AccentButton(this.label,
      {super.key, required this.onPressed, this.icon});

  /// Text displayed on this badge/button/statistic or derived from workout availability.
  final String label;

  /// Action supplied by the parent; null disables the primary button.
  final VoidCallback? onPressed;

  /// Optional or default icon displayed alongside the component’s text.
  final IconData? icon;

  /// Flutter calls this to describe the UI. context locates services/theme/navigation above this widget.
  @override
  Widget build(BuildContext context) => FilledButton(
        onPressed: onPressed,
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          if (icon != null) ...[Icon(icon, size: 19), const SizedBox(width: 8)],
          Text(label),
        ]),
      );
}

/// Card showing one number and label, used by TodayScreen and ProgressScreen.
class StatTile extends StatelessWidget {
  /// Creates StatTile; required arguments supply its dependencies or display data.
  const StatTile(
      {super.key,
      required this.number,
      required this.label,
      this.icon = Icons.bolt});

  /// Already-formatted statistic displayed prominently in a StatTile.
  final String number;

  /// Text displayed on this badge/button/statistic or derived from workout availability.
  final String label;

  /// Optional or default icon displayed alongside the component’s text.
  final IconData icon;

  /// Flutter calls this to describe the UI. context locates services/theme/navigation above this widget.
  @override
  Widget build(BuildContext context) => FitCard(
          child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: FitColors.peach),
          const SizedBox(height: 12),
          Text(number,
              style: Theme.of(context)
                  .textTheme
                  .headlineMedium
                  ?.copyWith(fontWeight: FontWeight.w900)),
          Text(label,
              style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ],
      ));
}

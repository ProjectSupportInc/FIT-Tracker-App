import 'package:flutter/material.dart';

import '../../app/fittracker_theme.dart';

class FitCard extends StatelessWidget {
  const FitCard({super.key, required this.child, this.padding = const EdgeInsets.all(18), this.onTap});
  final Widget child;
  final EdgeInsets padding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Card(
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      );
}

class SectionHeading extends StatelessWidget {
  const SectionHeading(this.title, {super.key, this.subtitle});
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w900, letterSpacing: -0.8)),
          if (subtitle != null) ...[
            const SizedBox(height: 6),
            Text(subtitle!, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ],
      );
}

class FitBadge extends StatelessWidget {
  const FitBadge(this.label, {super.key, this.highlight = false, this.icon});
  final String label;
  final bool highlight;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: highlight ? FitColors.lime : (dark ? const Color(0xFF254247) : FitColors.softGreen),
        borderRadius: BorderRadius.circular(30),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 13), const SizedBox(width: 5)],
        Text(label, style: TextStyle(
          fontSize: 11, fontWeight: FontWeight.w800,
          color: highlight ? FitColors.ink : null,
        )),
      ]),
    );
  }
}

class AccentButton extends StatelessWidget {
  const AccentButton(this.label, {super.key, required this.onPressed, this.icon});
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => FilledButton(
        onPressed: onPressed,
        child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          if (icon != null) ...[Icon(icon, size: 19), const SizedBox(width: 8)],
          Text(label),
        ]),
      );
}

class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.number, required this.label, this.icon = Icons.bolt});
  final String number;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) => FitCard(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: FitColors.peach),
          const SizedBox(height: 12),
          Text(number, style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w900)),
          Text(label, style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ],
      ));
}

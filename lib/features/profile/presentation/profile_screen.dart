// Shows the current user, toggles the theme, and signs the user out.
// Read docs/BEGINNER_GUIDE.md for the app flow and Dart syntax explanations.
// Imported by:
// - lib/features/shell/presentation/main_shell.dart

import 'package:flutter/material.dart';

import '../../../app/app_services.dart';
import '../../../app/fittracker_theme.dart';
import '../../../core/widgets/fit_widgets.dart';

/// Settings route opened by the account icon in MainShell.
class ProfileScreen extends StatelessWidget {
  /// Creates ProfileScreen; required arguments supply its dependencies or display data.
  const ProfileScreen({super.key, required this.theme});

  /// Theme controller passed from the root through MainShell into ProfileScreen.
  final ThemeViewModel theme;

  /// Flutter calls this to describe the UI. context locates services/theme/navigation above this widget.
  @override
  Widget build(BuildContext context) {
    // Shared authentication controller used for user data and sign-in/sign-out actions.
    final auth = AppServices.of(context).auth;
    // Current user record used to display name/email; may be null before sign-in.
    final user = auth.user;
    return Scaffold(
      appBar: AppBar(title: const Text('Profile & Settings')),
      body: ListView(padding: const EdgeInsets.all(22), children: [
        const CircleAvatar(radius: 42, child: Icon(Icons.person, size: 47)),
        const SizedBox(height: 15),
        Center(
            child: Text(user?.displayName ?? 'Athlete',
                style: const TextStyle(
                    fontSize: 23, fontWeight: FontWeight.w900))),
        Center(
            child: Text(user?.email ?? '',
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant))),
        const SizedBox(height: 31),
        FitCard(
            child: SwitchListTile(
          value: theme.isDark,
          onChanged: (_) => theme.toggle(),
          contentPadding: EdgeInsets.zero,
          title: const Text('Dark mode',
              style: TextStyle(fontWeight: FontWeight.w800)),
          secondary: Icon(theme.isDark ? Icons.dark_mode : Icons.light_mode,
              color: FitColors.lime),
        )),
        const SizedBox(height: 18),
        OutlinedButton.icon(
          onPressed: () async {
            try {
              await AppServices.of(context).workouts.endSession();
              await auth.signOut();
              if (context.mounted) Navigator.of(context).pop();
            } catch (error) {
              if (context.mounted) {
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text('$error')));
              }
            }
          },
          icon: const Icon(Icons.logout),
          label: const Text('Sign out'),
        ),
      ]),
    );
  }
}

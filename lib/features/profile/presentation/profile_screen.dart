import 'package:flutter/material.dart';

import '../../../app/app_services.dart';
import '../../../app/fittracker_theme.dart';
import '../../../core/widgets/fit_widgets.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key, required this.theme});
  final ThemeViewModel theme;

  @override
  Widget build(BuildContext context) {
    final auth = AppServices.of(context).auth;
    final user = auth.user;
    return Scaffold(
      appBar: AppBar(title: const Text('Profile & Settings')),
      body: ListView(padding: const EdgeInsets.all(22), children: [
        const CircleAvatar(radius: 42, child: Icon(Icons.person, size: 47)),
        const SizedBox(height: 15),
        Center(child: Text(user?.displayName ?? 'Athlete',
          style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w900))),
        Center(child: Text(user?.email ?? '',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))),
        const SizedBox(height: 31),
        FitCard(child: SwitchListTile(
          value: theme.isDark,
          onChanged: (_) => theme.toggle(),
          contentPadding: EdgeInsets.zero,
          title: const Text('Dark mode', style: TextStyle(fontWeight: FontWeight.w800)),
          secondary: Icon(theme.isDark ? Icons.dark_mode : Icons.light_mode,
              color: FitColors.lime),
        )),
        const SizedBox(height: 18),
        OutlinedButton.icon(
          onPressed: () async {
            Navigator.of(context).pop();
            await auth.signOut();
          },
          icon: const Icon(Icons.logout),
          label: const Text('Sign out'),
        ),
      ]),
    );
  }
}

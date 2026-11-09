import 'package:flutter/material.dart';
import '../../../app/app_services.dart';
import '../../../app/fittracker_theme.dart';
import '../../../core/widgets/fit_widgets.dart';

class SignInScreen extends StatelessWidget {
  const SignInScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final vm = AppServices.of(context).auth;
    return Scaffold(
      body: SafeArea(
        child: AnimatedBuilder(
          animation: vm,
          builder: (context, _) => Padding(
            padding: const EdgeInsets.all(28),
            child: Column(children: [
              const Spacer(flex: 2),
              Container(
                height: 124, width: 124,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [FitColors.lime, Color(0xFF79C96B)]),
                  borderRadius: BorderRadius.circular(35),
                ),
                child: const Icon(Icons.fitness_center_rounded, size: 65, color: FitColors.ink),
              ),
              const SizedBox(height: 34),
              Text('FITTRACKER', style: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w900, letterSpacing: 4)),
              const SizedBox(height: 13),
              Text('Train with intent.\nMove with power.', textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineLarge?.copyWith(
                  fontWeight: FontWeight.w900, height: 1.06, letterSpacing: -1.4,
                )),
              const SizedBox(height: 16),
              Text('Your next rep starts here.',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
              const Spacer(flex: 2),
              AccentButton(vm.isBusy ? 'Signing in...' : 'Continue with Google',
                icon: Icons.login_rounded,
                onPressed: vm.isBusy ? null : () => vm.signIn()),
              if (vm.error != null) ...[
                const SizedBox(height: 12),
                Text(vm.error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
              const SizedBox(height: 22),
            ]),
          ),
        ),
      ),
    );
  }
}

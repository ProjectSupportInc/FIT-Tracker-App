// Simulates authentication with a fixed demo user; no Google request is made.
// Read docs/BEGINNER_GUIDE.md for the app flow and Dart syntax explanations.
// Imported by:
// - lib/app/fittracker_app.dart

import 'auth_repository.dart';

/// Local development adapter. Does not authenticate with Google.
/// Demo implementation selected in fittracker_app.dart; always returns the sample user.
class MockAuthRepository implements AuthRepository {
  /// Returns a user to AuthViewModel.signIn(); the mock implementation does not contact Google.
  @override
  Future<AppUser> signInWithGoogle() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return const AppUser(
      id: 'demo-athlete-01',
      displayName: 'Jordan Lee',
      email: 'jordan@example.com',
    );
  }

  /// Ends the current sign-in session. ProfileScreen calls the controller, which calls the repository.
  @override
  Future<void> signOut() async {}
}

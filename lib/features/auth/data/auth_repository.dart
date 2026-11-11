// Defines the signed-in user data and the contract that authentication adapters must implement.
// Read docs/BEGINNER_GUIDE.md for the app flow and Dart syntax explanations.
// Imported by:
// - lib/features/auth/data/mock_auth_repository.dart
// - lib/features/auth/presentation/auth_view_model.dart

/// User record returned by AuthRepository and displayed by TodayScreen and ProfileScreen.
class AppUser {
  /// Creates AppUser; required arguments supply its dependencies or display data.
  const AppUser(
      {required this.id, required this.displayName, required this.email});

  /// Stable identifier used for lookups and comparisons; display labels may change independently.
  final String id;

  /// User-visible name shown by TodayScreen and ProfileScreen.
  final String displayName;

  /// User email displayed by ProfileScreen.
  final String email;
}

/// Authentication contract consumed by AuthViewModel; MockAuthRepository implements it.
abstract class AuthRepository {
  /// Returns a user to AuthViewModel.signIn(); the mock implementation does not contact Google.
  Future<AppUser> signInWithGoogle();

  /// Ends the current sign-in session. ProfileScreen calls the controller, which calls the repository.
  Future<void> signOut();
}

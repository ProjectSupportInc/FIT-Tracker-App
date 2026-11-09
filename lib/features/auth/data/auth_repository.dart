class AppUser {
  const AppUser({required this.id, required this.displayName, required this.email});
  final String id;
  final String displayName;
  final String email;
}

abstract class AuthRepository {
  Future<AppUser> signInWithGoogle();
  Future<void> signOut();
}

import 'auth_repository.dart';

/// Local development adapter. Does not authenticate with Google.
class MockAuthRepository implements AuthRepository {
  @override
  Future<AppUser> signInWithGoogle() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    return const AppUser(
      id: 'demo-athlete-01',
      displayName: 'Jordan Lee',
      email: 'jordan@example.com',
    );
  }

  @override
  Future<void> signOut() async {}
}

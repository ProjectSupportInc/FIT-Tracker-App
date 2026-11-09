import 'package:flutter/foundation.dart';
import '../data/auth_repository.dart';

class AuthViewModel extends ChangeNotifier {
  AuthViewModel(this._repository);
  final AuthRepository _repository;
  AppUser? _user;
  bool _busy = false;
  String? _error;

  AppUser? get user => _user;
  bool get isSignedIn => _user != null;
  bool get isBusy => _busy;
  String? get error => _error;

  Future<void> signIn() async {
    if (_busy) return;
    _busy = true;
    _error = null;
    notifyListeners();
    try {
      _user = await _repository.signInWithGoogle();
    } catch (error) {
      _error = 'Unable to sign in. Please try again.';
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    await _repository.signOut();
    _user = null;
    notifyListeners();
  }
}

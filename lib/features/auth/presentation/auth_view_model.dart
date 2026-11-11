// Owns sign-in state and tells listening widgets when the user, busy flag, or error changes.
// Read docs/BEGINNER_GUIDE.md for the app flow and Dart syntax explanations.
// Imported by:
// - lib/app/app_services.dart
// - lib/app/fittracker_app.dart

import 'package:flutter/foundation.dart';
import '../data/auth_repository.dart';

/// Authentication controller created by FitTrackerApp; SignInScreen and ProfileScreen call it.
class AuthViewModel extends ChangeNotifier {
  /// Creates AuthViewModel; required arguments supply its dependencies or display data.
  AuthViewModel(this._repository);

  /// Injected authentication adapter called by signIn() and signOut().
  final AuthRepository _repository;

  /// Current signed-in user; null means signed out.
  AppUser? _user;

  /// Prevents repeated actions while an asynchronous request or confirmation is in progress.
  bool _busy = false;

  /// Last sign-in error message shown by SignInScreen; null means no error.
  String? _error;

  /// Current user record used to display name/email; may be null before sign-in.
  AppUser? get user => _user;

  /// Whether a user is present; FitTrackerApp uses this to choose sign-in or the tabs.
  bool get isSignedIn => _user != null;

  /// Whether sign-in is pending; disables the sign-in button and changes its label.
  bool get isBusy => _busy;

  /// Read-only sign-in error text displayed by SignInScreen.
  String? get error => _error;

  /// Handles the SignInScreen button: sets loading state, requests a user, and exposes any error.
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

  /// Ends the current sign-in session. ProfileScreen calls the controller, which calls the repository.
  Future<void> signOut() async {
    await _repository.signOut();
    _user = null;
    notifyListeners();
  }
}

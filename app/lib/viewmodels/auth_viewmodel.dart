import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:repiq/services/auth_service.dart';

/// Manages Firebase Authentication state and exposes it to the widget tree.
class AuthViewModel extends ChangeNotifier {
  final _service = AuthService();

  User? _user;
  bool _isSigningIn = false;
  String? _error;
  StreamSubscription<User?>? _authSub;

  User? get user => _user;
  bool get isSignedIn => _user != null;
  bool get isSigningIn => _isSigningIn;
  String? get error => _error;

  AuthViewModel() {
    _authSub = _service.authStateChanges.listen((user) {
      _user = user;
      notifyListeners();
    });
  }

  /// Signs in with Google. Sets [isSigningIn] while the flow is in progress.
  Future<void> signIn() async {
    _isSigningIn = true;
    _error = null;
    notifyListeners();
    try {
      await _service.signInWithGoogle();
    } catch (e) {
      _error = 'Sign-in failed. Please try again.';
      notifyListeners();
    } finally {
      _isSigningIn = false;
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    await _service.signOut();
  }

  /// Returns a fresh ID token for use in API request headers.
  Future<String?> getIdToken() => _service.getIdToken();

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }
}

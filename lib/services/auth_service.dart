import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  User? get currentUser => _auth.currentUser;

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  Future<User> signIn(String email, String password) async {
    final cred = await _auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    return cred.user!;
  }

  Future<User> register(String name, String email, String password) async {
    final cred = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    await cred.user!.updateDisplayName(name.trim());
    // Reload so currentUser.displayName is populated immediately
    await cred.user!.reload();
    return _auth.currentUser!;
  }

  Future<void> sendPasswordReset(String email) async {
    await _auth.sendPasswordResetEmail(email: email.trim());
  }

  Future<void> signOut() async {
    final prefs = await SharedPreferences.getInstance();
    final userKeys = prefs.getKeys().where(
      (key) => key.startsWith('cache_') || key == 'phase56_outbox',
    );
    for (final key in userKeys.toList()) {
      await prefs.remove(key);
    }
    await _auth.signOut();
    debugPrint('AuthService: signed out');
  }

  /// Returns a fresh ID token. Firebase caches and auto-refreshes it.
  Future<String?> getIdToken() async {
    try {
      return await _auth.currentUser?.getIdToken();
    } catch (e) {
      debugPrint('AuthService.getIdToken error: $e');
      return null;
    }
  }
}

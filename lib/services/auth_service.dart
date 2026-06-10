import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:metrosafar/services/sync/outbox.dart';

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
    final uid = _auth.currentUser?.uid;
    // Clear all UID-scoped caches and the offline outbox before sign-out so the
    // next signed-in user cannot see the previous user's cached data.
    try {
      final prefs = await SharedPreferences.getInstance();
      if (uid != null) {
        final keys = prefs.getKeys().where((k) => k.startsWith('${uid}_')).toList();
        for (final k in keys) await prefs.remove(k);
      }
      await Outbox().replaceAll([]); // queued mutations carry the old user's auth headers
    } catch (e) {
      debugPrint('AuthService: cache clear error on sign-out: $e');
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

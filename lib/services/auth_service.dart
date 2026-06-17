import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

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

  /// Starts phone-number verification. Firebase sends a 6-digit SMS code.
  ///
  /// On Android the code can be auto-retrieved or instantly verified, in which
  /// case [verificationCompleted] fires with a ready-to-use credential and the
  /// user never has to type anything. On iOS the user always enters the code,
  /// so [codeSent] fires and you complete via [signInWithSmsCode].
  ///
  /// Pass [forceResendingToken] (from a previous [codeSent]) to resend without
  /// triggering Firebase's abuse throttling.
  Future<void> verifyPhone({
    required String phoneNumber,
    required void Function(String verificationId, int? resendToken) codeSent,
    required void Function(FirebaseAuthException e) verificationFailed,
    required void Function(PhoneAuthCredential credential)
        verificationCompleted,
    int? forceResendingToken,
  }) async {
    await _auth.verifyPhoneNumber(
      phoneNumber: phoneNumber,
      timeout: const Duration(seconds: 60),
      forceResendingToken: forceResendingToken,
      verificationCompleted: verificationCompleted,
      verificationFailed: verificationFailed,
      codeSent: codeSent,
      codeAutoRetrievalTimeout: (_) {},
    );
  }

  /// Completes phone sign-in with the SMS code the user typed.
  Future<User> signInWithSmsCode({
    required String verificationId,
    required String smsCode,
  }) async {
    final credential = PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: smsCode.trim(),
    );
    final cred = await _auth.signInWithCredential(credential);
    return cred.user!;
  }

  /// Completes phone sign-in from an auto-retrieved/instant credential.
  Future<User> signInWithPhoneCredential(
    PhoneAuthCredential credential,
  ) async {
    final cred = await _auth.signInWithCredential(credential);
    return cred.user!;
  }

  Future<void> signOut() async {
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

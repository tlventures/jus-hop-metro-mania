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

  // ---------------------------------------------------------------------------
  // Phone verification (anti-Sybil). The phone is linked as a second credential
  // on the existing email account; the backend then sees a verified
  // phone_number claim in every ID token. Firebase enforces one phone = one
  // account project-wide.
  // ---------------------------------------------------------------------------

  bool get isPhoneVerified => (_auth.currentUser?.phoneNumber ?? '').isNotEmpty;

  /// Fires on sign-in/out AND profile changes (e.g. after a phone link).
  Stream<User?> get userChanges => _auth.userChanges();

  /// Starts OTP delivery. On Android, instant verification or SMS
  /// auto-retrieval may complete the link with no typing — then [onVerified]
  /// fires without [onCodeSent].
  Future<void> startPhoneVerification({
    required String phoneE164,
    required void Function(String verificationId, int? resendToken) onCodeSent,
    required void Function(String message) onFailed,
    required void Function() onVerified,
    int? resendToken,
  }) async {
    await _auth.verifyPhoneNumber(
      phoneNumber: phoneE164,
      forceResendingToken: resendToken,
      timeout: const Duration(seconds: 60),
      verificationCompleted: (credential) async {
        try {
          await _linkPhoneCredential(credential);
          onVerified();
        } catch (e) {
          onFailed(friendlyPhoneError(e));
        }
      },
      verificationFailed: (e) => onFailed(friendlyPhoneError(e)),
      codeSent: onCodeSent,
      codeAutoRetrievalTimeout: (_) {},
    );
  }

  Future<void> confirmSmsCode(String verificationId, String smsCode) async {
    final credential = PhoneAuthProvider.credential(
      verificationId: verificationId,
      smsCode: smsCode.trim(),
    );
    await _linkPhoneCredential(credential);
  }

  Future<void> _linkPhoneCredential(PhoneAuthCredential credential) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw FirebaseAuthException(code: 'no-current-user');
    }
    try {
      await user.linkWithCredential(credential);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'provider-already-linked') {
        // Account already has a phone — the user is changing their number.
        await user.updatePhoneNumber(credential);
      } else {
        rethrow;
      }
    }
    await user.reload();
    // Force-refresh so the backend sees the phone_number claim immediately
    // instead of when the cached token expires (~1 hour).
    await _auth.currentUser?.getIdToken(true);
  }

  String friendlyPhoneError(Object e) {
    final raw = e.toString();
    if (raw.contains('credential-already-in-use') ||
        raw.contains('account-exists-with-different-credential')) {
      return 'This phone number is already linked to another account.';
    }
    if (raw.contains('invalid-verification-code')) {
      return 'That code is incorrect. Please check and try again.';
    }
    if (raw.contains('invalid-phone-number')) {
      return 'Please enter a valid 10-digit mobile number.';
    }
    if (raw.contains('too-many-requests')) {
      return 'Too many attempts. Please try again later.';
    }
    if (raw.contains('session-expired') || raw.contains('code-expired')) {
      return 'The code expired. Tap Resend to get a new one.';
    }
    if (raw.contains('network-request-failed')) return 'No internet connection.';
    return 'Verification failed. Please try again.';
  }

  Future<void> signOut() async {
    final uid = _auth.currentUser?.uid;
    // Clear all UID-scoped caches and the offline outbox before sign-out so the
    // next signed-in user cannot see the previous user's cached data.
    try {
      final prefs = await SharedPreferences.getInstance();
      if (uid != null) {
        final keys = prefs.getKeys().where((k) => k.startsWith('${uid}_')).toList();
        for (final k in keys) {
          await prefs.remove(k);
        }
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

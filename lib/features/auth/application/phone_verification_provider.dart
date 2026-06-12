import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether the signed-in user has a verified phone number linked.
///
/// Uses userChanges() (not authStateChanges) so it fires immediately after a
/// phone credential is linked and the user is reloaded — earning surfaces
/// watching this unlock without an app restart.
final phoneVerifiedProvider = StreamProvider<bool>((ref) {
  return FirebaseAuth.instance
      .userChanges()
      .map((user) => (user?.phoneNumber ?? '').isNotEmpty);
});

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Central source of truth for whether the current user is under 18.
///
/// Storage: the DOB / minor classification / parental-consent flags are kept in
/// [FlutterSecureStorage] (Android Keystore / iOS Keychain) rather than plain
/// SharedPreferences. This matters for DPDPA §9 — if the flag lived in
/// SharedPreferences a user could clear app data (or a cloud restore could land
/// stale data) and silently flip a minor back to the adult default, re-enabling
/// ads and analytics. Secure storage is encrypted, excluded from backup, and
/// not trivially editable.
///
/// [hydrate()] warms a synchronous [isMinorCached] flag once at boot so the gate
/// can be read without awaiting on every frame.
///
/// Gates:
///   • AdMob (both banner and rewarded) — via AdMobConfig.adsEnabled getter
///   • Firebase Analytics collection
///   • Background GPS polling in CommuteDetector
class MinorStatus {
  MinorStatus._();

  static const _kDob = 'user_dob';        // ISO yyyy-MM-dd (store date only)
  static const _kIsMinor = 'user_is_minor'; // 'true' / 'false'
  static const _kParentVerified = 'parent_consent_verified'; // 'true' / 'false'

  static const _secure = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
  );

  /// Synchronous flag cached after [hydrate()] resolves.
  /// Defaults false (safe: show ads/analytics until DOB confirmed) because
  /// pre-existing installs without a stored DOB are adults by assumption.
  static bool isMinorCached = false;

  /// Call this once at boot (before runApp) to warm the synchronous cache.
  /// Also performs a one-time migration of any legacy SharedPreferences values
  /// written by older builds, then clears them so secure storage is the only
  /// source of truth going forward.
  static Future<void> hydrate() async {
    await _migrateFromSharedPreferencesIfNeeded();
    final raw = await _secure.read(key: _kIsMinor);
    isMinorCached = raw == 'true';
  }

  /// Persist the user's date of birth and compute the minor flag.
  static Future<void> setDob(DateTime dob) async {
    final age = _age(dob);
    final minor = age < 18;
    await _secure.write(
      key: _kDob,
      value: dob.toIso8601String().substring(0, 10),
    );
    await _secure.write(key: _kIsMinor, value: minor ? 'true' : 'false');
    isMinorCached = minor;
  }

  /// Whether the parent has completed the email-link verification.
  static Future<bool> get parentVerified async =>
      (await _secure.read(key: _kParentVerified)) == 'true';

  static Future<void> setParentVerified() async {
    await _secure.write(key: _kParentVerified, value: 'true');
  }

  /// Computed age from stored DOB.  Returns null if no DOB stored.
  static Future<int?> get age async {
    final dob = await _secure.read(key: _kDob);
    if (dob == null) return null;
    final dobDate = DateTime.tryParse(dob);
    if (dobDate == null) return null;
    return _age(dobDate);
  }

  /// Moves legacy plaintext values from SharedPreferences into secure storage
  /// exactly once, preserving the more-conservative classification, then
  /// removes the legacy keys. No-op once secure storage already holds a value.
  static Future<void> _migrateFromSharedPreferencesIfNeeded() async {
    final existing = await _secure.read(key: _kIsMinor);
    if (existing != null) return; // already migrated / set

    final prefs = await SharedPreferences.getInstance();
    final legacyDob = prefs.getString(_kDob);
    final legacyMinor = prefs.getBool(_kIsMinor);
    final legacyParent = prefs.getBool(_kParentVerified);
    if (legacyDob == null && legacyMinor == null && legacyParent == null) {
      return; // nothing to migrate
    }

    if (legacyDob != null) await _secure.write(key: _kDob, value: legacyDob);
    if (legacyMinor != null) {
      await _secure.write(key: _kIsMinor, value: legacyMinor ? 'true' : 'false');
    }
    if (legacyParent == true) {
      await _secure.write(key: _kParentVerified, value: 'true');
    }

    await prefs.remove(_kDob);
    await prefs.remove(_kIsMinor);
    await prefs.remove(_kParentVerified);
  }

  static int _age(DateTime dob) {
    final now = DateTime.now();
    var a = now.year - dob.year;
    if (now.month < dob.month ||
        (now.month == dob.month && now.day < dob.day)) {
      a--;
    }
    return a;
  }
}

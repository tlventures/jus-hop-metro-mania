import 'package:shared_preferences/shared_preferences.dart';

/// Central source of truth for whether the current user is under 18.
///
/// Defaults to [isMinorCached] = false at startup (treat as adult) until
/// [hydrate()] has been called from main.dart.  [setDob()] persists the
/// classification to SharedPreferences so it survives restarts.
///
/// Gates:
///   • AdMob (both banner and rewarded) — via AdMobConfig.adsEnabled getter
///   • Firebase Analytics collection
///   • Background GPS polling in CommunteDetector
class MinorStatus {
  MinorStatus._();

  static const _kDob = 'user_dob';        // ISO yyyy-MM-dd (store date only)
  static const _kIsMinor = 'user_is_minor'; // bool
  static const _kParentVerified = 'parent_consent_verified'; // bool

  /// Synchronous flag cached after [hydrate()] resolves.
  /// Defaults false (safe: show ads/analytics until DOB confirmed) because
  /// pre-existing installs without a stored DOB are adults by assumption.
  static bool isMinorCached = false;

  /// Call this once at boot (before runApp) to warm the synchronous cache.
  static Future<void> hydrate() async {
    final p = await SharedPreferences.getInstance();
    isMinorCached = p.getBool(_kIsMinor) ?? false;
  }

  /// Persist the user's date of birth and compute the minor flag.
  static Future<void> setDob(DateTime dob) async {
    final p = await SharedPreferences.getInstance();
    final age = _age(dob);
    final minor = age < 18;
    await p.setString(_kDob, dob.toIso8601String().substring(0, 10));
    await p.setBool(_kIsMinor, minor);
    isMinorCached = minor;
  }

  /// Whether the parent has completed the email-link verification.
  static Future<bool> get parentVerified async =>
      (await SharedPreferences.getInstance()).getBool(_kParentVerified) ?? false;

  static Future<void> setParentVerified() async {
    final p = await SharedPreferences.getInstance();
    await p.setBool(_kParentVerified, true);
  }

  /// Computed age from stored DOB.  Returns null if no DOB stored.
  static Future<int?> get age async {
    final p = await SharedPreferences.getInstance();
    final dob = p.getString(_kDob);
    if (dob == null) return null;
    final dobDate = DateTime.tryParse(dob);
    if (dobDate == null) return null;
    return _age(dobDate);
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

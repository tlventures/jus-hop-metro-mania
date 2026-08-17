import 'package:flutter/foundation.dart';
import '../core/compliance/minor_status.dart';

class AdMobConfig {
  AdMobConfig._();

  /// Returns false for under-18 users (DPDPA §9 — no ads to minors),
  /// and false when the compile-time flag is off (e.g. test builds).
  /// Runtime getter so it can read [MinorStatus.isMinorCached].
  static bool get adsEnabled {
    if (MinorStatus.isMinorCached) return false;
    return const bool.fromEnvironment(
      'METROSAFAR_ADS_ENABLED',
      defaultValue: true,
    );
  }

  // Google's publicly-documented test ID prefix.
  static const String _testIdPrefix = 'ca-app-pub-3940256099942544';

  static const String androidBannerAdUnitId = String.fromEnvironment(
    'ADMOB_ANDROID_BANNER_UNIT_ID',
    defaultValue: 'ca-app-pub-3940256099942544/6300978111',
  );

  // Rewarded ad ("watch & earn"). Default is Google's public TEST unit —
  // replace with the real unit ID before Play Store launch.
  static const String androidRewardedAdUnitId = String.fromEnvironment(
    'ADMOB_ANDROID_REWARDED_UNIT_ID',
    defaultValue: 'ca-app-pub-3940256099942544/5224354917',
  );

  /// Call once during bootstrap (after [adsEnabled] is known) to crash early
  /// if a release build still carries test ad unit IDs.
  ///
  /// This mirrors the safety pattern in [ApiConfig] — asserts are stripped in
  /// production but fire loudly in debug/profile and CI, catching a
  /// misconfigured build before it reaches the Play Store.
  static void assertProductionIds() {
    if (!adsEnabled) return; // ads disabled entirely — nothing to guard

    assert(
      !kReleaseMode || !androidBannerAdUnitId.startsWith(_testIdPrefix),
      'ADMOB_ANDROID_BANNER_UNIT_ID is still the Google test ID. '
      'Supply the real unit ID via --dart-define for release builds.',
    );
    assert(
      !kReleaseMode || !androidRewardedAdUnitId.startsWith(_testIdPrefix),
      'ADMOB_ANDROID_REWARDED_UNIT_ID is still the Google test ID. '
      'Supply the real unit ID via --dart-define for release builds.',
    );
  }
}

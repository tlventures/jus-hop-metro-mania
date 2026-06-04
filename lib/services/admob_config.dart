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
}

class AdMobConfig {
  AdMobConfig._();

  static const bool adsEnabled = bool.fromEnvironment(
    'METROSAFAR_ADS_ENABLED',
    defaultValue: true,
  );

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

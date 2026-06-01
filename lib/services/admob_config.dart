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
}

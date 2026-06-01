import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../../services/admob_config.dart';

class MetroSafarAdBanner extends StatefulWidget {
  const MetroSafarAdBanner({super.key});

  @override
  State<MetroSafarAdBanner> createState() => _MetroSafarAdBannerState();
}

class _MetroSafarAdBannerState extends State<MetroSafarAdBanner> {
  BannerAd? _ad;
  bool _isLoaded = false;

  @override
  void initState() {
    super.initState();
    if (!AdMobConfig.adsEnabled || kIsWeb || !Platform.isAndroid) return;
    _ad = BannerAd(
      size: AdSize.banner,
      adUnitId: AdMobConfig.androidBannerAdUnitId,
      listener: BannerAdListener(
        onAdLoaded: (_) {
          if (mounted) setState(() => _isLoaded = true);
        },
        onAdFailedToLoad: (ad, error) {
          debugPrint('AdMob banner failed to load: $error');
          ad.dispose();
        },
      ),
      request: const AdRequest(nonPersonalizedAds: true),
    )..load();
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ad = _ad;
    if (!_isLoaded || ad == null) return const SizedBox.shrink();

    return SafeArea(
      top: false,
      bottom: false,
      child: SizedBox(
        height: ad.size.height.toDouble(),
        width: double.infinity,
        child: Center(
          child: SizedBox(
            height: ad.size.height.toDouble(),
            width: ad.size.width.toDouble(),
            child: AdWidget(ad: ad),
          ),
        ),
      ),
    );
  }
}

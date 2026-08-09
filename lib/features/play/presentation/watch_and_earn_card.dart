import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../../../design_system/tokens/colors.dart';
import '../../../design_system/tokens/radius.dart';
import '../../../design_system/tokens/spacing.dart';
import '../../../design_system/tokens/typography.dart';
import '../../../services/admob_config.dart';
import '../../wallet/application/promo_provider.dart';
import '../../wallet/data/rewards_service.dart';

/// "Watch a video, earn points" — shows a rewarded ad and credits points
/// (server-enforced daily cap) when the user finishes watching.
class WatchAndEarnCard extends ConsumerStatefulWidget {
  const WatchAndEarnCard({super.key});

  @override
  ConsumerState<WatchAndEarnCard> createState() => _WatchAndEarnCardState();
}

class _WatchAndEarnCardState extends ConsumerState<WatchAndEarnCard> {
  RewardedAd? _ad;
  bool _loading = false;
  bool _showing = false;

  @override
  void initState() {
    super.initState();
    if (AdMobConfig.adsEnabled) _loadAd();
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  void _loadAd() {
    if (_loading || _ad != null) return;
    _loading = true;
    RewardedAd.load(
      adUnitId: AdMobConfig.androidRewardedAdUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          if (!mounted) {
            ad.dispose();
            return;
          }
          setState(() {
            _ad = ad;
            _loading = false;
          });
        },
        onAdFailedToLoad: (err) {
          debugPrint('RewardedAd load failed: $err');
          if (mounted) setState(() => _loading = false);
        },
      ),
    );
  }

  Future<void> _watch() async {
    final ad = _ad;
    if (ad == null || _showing) return;
    setState(() => _showing = true);

    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        if (mounted) {
          setState(() {
            _ad = null;
            _showing = false;
          });
          _loadAd(); // preload the next one
        }
      },
      onAdFailedToShowFullScreenContent: (ad, err) {
        ad.dispose();
        if (mounted) {
          setState(() {
            _ad = null;
            _showing = false;
          });
          _loadAd();
        }
      },
    );

    // Pass the Firebase UID via SSV options so AdMob echoes it back in the
    // server-side callback (GET /api/rewards/admob-ssv?user_id=...).
    // Points are awarded server-side; the client just shows a confirmation.
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    await ad.setServerSideOptions(
      ServerSideVerificationOptions(
        userId: uid,
        customData: 'metrosafar_reward_v1',
      ),
    );
    await ad.show(
      onUserEarnedReward: (_, reward) async {
        if (!mounted) return;
        // Credit via our unified earn endpoint. AdMob SSV is stronger for
        // production; this is the client-declared path until SSV is verified
        // in prod. Idempotency-Key uses the user+ad+timestamp so replay is
        // rejected by the backend.
        final eventId = 'ad:$uid:${DateTime.now().millisecondsSinceEpoch}';
        try {
          final res = await RewardsService().earn(
            source: 'AD_WATCH',
            eventId: eventId,
          );
          ref.invalidate(walletBalanceProvider);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  res.pointsAwarded > 0
                      ? 'Earned ${res.pointsAwarded} pts · ${res.dayCapRemainingSource} more today'
                      : 'Daily ad cap reached — come back tomorrow',
                ),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Could not credit reward: $e')),
            );
          }
        }
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!AdMobConfig.adsEnabled) return const SizedBox.shrink();
    final colorScheme = Theme.of(context).colorScheme;
    final ready = _ad != null && !_showing;

    return GestureDetector(
      onTap: ready ? _watch : null,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.s4),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              AppColors.goldPoints.withValues(alpha: 0.18),
              AppColors.goldPoints.withValues(alpha: 0.06),
            ],
          ),
          borderRadius: AppRadius.borderRadiusXL,
          border: Border.all(
            color: AppColors.goldPoints.withValues(alpha: 0.35),
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.s3),
              decoration: BoxDecoration(
                color: AppColors.goldPoints.withValues(alpha: 0.2),
                borderRadius: AppRadius.borderRadiusM,
              ),
              child: const Icon(
                Icons.play_circle_fill,
                color: AppColors.goldPoints,
              ),
            ),
            const SizedBox(width: AppSpacing.s4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Watch & Earn',
                    style: AppTypography.titleSmall.copyWith(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    ready
                        ? 'Watch a short video, earn +10 pts'
                        : 'Loading a video…',
                    style: AppTypography.bodySmall.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            if (!ready)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              const Icon(Icons.chevron_right, color: AppColors.goldPoints),
          ],
        ),
      ),
    );
  }
}

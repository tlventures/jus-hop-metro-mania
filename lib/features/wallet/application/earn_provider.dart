// lib/features/wallet/application/earn_provider.dart
//
// Providers for the *earn* surfaces (streak, ad, referral) — kept separate
// from the pre-existing `rewards_provider.dart` which handles the redemption
// catalog (Reward-marketplace).

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/rewards_service.dart';

final earnServiceProvider = Provider<RewardsService>((_) => RewardsService());

final streakStatusProvider = FutureProvider.autoDispose<StreakStatus>((ref) {
  return ref.watch(earnServiceProvider).getStreak();
});

final referralCodeProvider = FutureProvider.autoDispose<ReferralCode>((ref) {
  return ref.watch(earnServiceProvider).getReferralCode();
});

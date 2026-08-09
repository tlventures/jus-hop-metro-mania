// lib/features/wallet/application/promo_provider.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/promo_service.dart';

final promoServiceProvider = Provider<PromoService>((_) => PromoService());

final walletBalanceProvider = FutureProvider.autoDispose<WalletBalance>((ref) {
  return ref.watch(promoServiceProvider).fetchBalance();
});

final promoCodesProvider = FutureProvider.autoDispose<List<PromoCodeItem>>((ref) {
  return ref.watch(promoServiceProvider).listCodes();
});

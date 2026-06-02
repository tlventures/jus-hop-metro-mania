import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../domain/entities/activity_event.dart';
import '../../../services/backend_service.dart';

class WalletState {
  final int points;
  final String tier;
  final double tierProgress;
  final int pointsToNextTier;
  final String nextTier;
  final bool isLoading;
  final List<WalletTransaction> transactions;
  final bool transactionsLoading;

  const WalletState({
    this.points = 0,
    this.tier = 'Bronze',
    this.tierProgress = 0.0,
    this.pointsToNextTier = 500,
    this.nextTier = 'Silver',
    this.isLoading = true,
    this.transactions = const [],
    this.transactionsLoading = false,
  });

  String get tierEmoji {
    switch (tier.toLowerCase()) {
      case 'platinum': return '💎';
      case 'gold':     return '🥇';
      case 'silver':   return '🥈';
      case 'bronze':   return '🥉';
      default:         return '🥉';
    }
  }

  String get tierDisplay => '$tier $tierEmoji';

  WalletState copyWith({
    int? points,
    String? tier,
    double? tierProgress,
    int? pointsToNextTier,
    String? nextTier,
    bool? isLoading,
    List<WalletTransaction>? transactions,
    bool? transactionsLoading,
  }) {
    return WalletState(
      points: points ?? this.points,
      tier: tier ?? this.tier,
      tierProgress: tierProgress ?? this.tierProgress,
      pointsToNextTier: pointsToNextTier ?? this.pointsToNextTier,
      nextTier: nextTier ?? this.nextTier,
      isLoading: isLoading ?? this.isLoading,
      transactions: transactions ?? this.transactions,
      transactionsLoading: transactionsLoading ?? this.transactionsLoading,
    );
  }
}

class WalletNotifier extends StateNotifier<WalletState> {
  final BackendService _backendService;
  bool _disposed = false;

  WalletNotifier(this._backendService) : super(const WalletState());

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// Hydrate points + tier from the /api/home aggregate.
  /// Full transaction list is still fetched separately by the wallet tab.
  void hydrateFromHomeData(Map<String, dynamic> walletData) {
    if (_disposed) return;
    final points = (walletData['points'] as num?)?.toInt() ?? state.points;
    final tier = walletData['membershipTier'] as String? ?? state.tier;
    final (progress, ptsToNext, nextTier) = _computeTier(points, tier);
    state = state.copyWith(
      points: points,
      tier: tier,
      tierProgress: progress,
      pointsToNextTier: ptsToNext,
      nextTier: nextTier,
      isLoading: false,
    );
  }

  Future<void> fetchWallet() async {
    try {
      final data = await _backendService.getProfile();
      if (_disposed) return;
      final profile = data['profile'] as Map<String, dynamic>? ?? data;
      final points = (profile['points'] as num?)?.toInt() ?? 0;
      final tier = profile['membershipTier'] as String? ?? 'Bronze';
      final (progress, ptsToNext, nextTier) = _computeTier(points, tier);

      state = state.copyWith(
        points: points,
        tier: tier,
        tierProgress: progress,
        pointsToNextTier: ptsToNext,
        nextTier: nextTier,
        isLoading: false,
      );
    } catch (e) {
      debugPrint('WalletNotifier.fetchWallet error: $e');
      if (!_disposed) state = state.copyWith(isLoading: false);
    }
  }

  Future<void> fetchTransactions() async {
    if (_disposed) return;
    state = state.copyWith(transactionsLoading: true);
    try {
      final data = await _backendService.getWalletTransactions();
      if (_disposed) return;
      final raw = data['transactions'] as List<dynamic>? ?? [];
      final txns = raw
          .map((t) => WalletTransaction.fromJson(t as Map<String, dynamic>))
          .toList();
      state = state.copyWith(transactions: txns, transactionsLoading: false);
    } catch (e) {
      debugPrint('WalletNotifier.fetchTransactions error: $e');
      if (!_disposed) state = state.copyWith(transactionsLoading: false);
    }
  }

  Future<bool> redeemReward(String rewardId, int cost) async {
    if (state.points < cost) return false;
    try {
      await _backendService.redeemReward(rewardId);
      final newPoints = state.points - cost;
      final (progress, ptsToNext, nextTier) = _computeTier(newPoints, state.tier);
      state = state.copyWith(
        points: newPoints,
        tierProgress: progress,
        pointsToNextTier: ptsToNext,
        nextTier: nextTier,
      );
      return true;
    } catch (e) {
      debugPrint('WalletNotifier.redeemReward error: $e');
      return false;
    }
  }

  // Update local balance after an activity event completes
  void applyPointsAwarded(int pts) {
    if (pts <= 0) return;
    final newPoints = state.points + pts;
    final (progress, ptsToNext, nextTier) = _computeTier(newPoints, state.tier);
    state = state.copyWith(
      points: newPoints,
      tierProgress: progress,
      pointsToNextTier: ptsToNext,
      nextTier: nextTier,
    );
  }

  // Must match server.js getTier() / getNextTier() thresholds:
  // Bronze (0-299) → Silver (300-599) → Gold (600-999) → Platinum (1000+)
  static (double, int, String) _computeTier(int points, String currentTier) {
    if (points < 300) {
      return ((points / 300.0).clamp(0.0, 1.0), 300 - points, 'Silver');
    } else if (points < 600) {
      return (((points - 300) / 300.0).clamp(0.0, 1.0), 600 - points, 'Gold');
    } else if (points < 1000) {
      return (((points - 600) / 400.0).clamp(0.0, 1.0), 1000 - points, 'Platinum');
    } else {
      return (1.0, 0, 'Platinum');
    }
  }
}

final walletServiceProvider = Provider((ref) => BackendService());

final walletProvider = StateNotifierProvider<WalletNotifier, WalletState>((ref) {
  return WalletNotifier(ref.watch(walletServiceProvider));
});

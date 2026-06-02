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

  /// True when the most recent earn hit the daily point cap. UI should show
  /// "daily limit reached" instead of a (zero) points-earned toast.
  final bool dailyCapReached;
  final int dailyEarned;
  final int dailyCap;

  const WalletState({
    this.points = 0,
    this.tier = 'Bronze',
    this.tierProgress = 0.0,
    this.pointsToNextTier = 500,
    this.nextTier = 'Silver',
    this.isLoading = true,
    this.transactions = const [],
    this.transactionsLoading = false,
    this.dailyCapReached = false,
    this.dailyEarned = 0,
    this.dailyCap = 500,
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
    bool? dailyCapReached,
    int? dailyEarned,
    int? dailyCap,
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
      dailyCapReached: dailyCapReached ?? this.dailyCapReached,
      dailyEarned: dailyEarned ?? this.dailyEarned,
      dailyCap: dailyCap ?? this.dailyCap,
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
      final result = await _backendService.redeemReward(rewardId);
      // Trust the server's returned balance instead of local subtraction.
      final serverPoints = (result['points'] as num?)?.toInt();
      final newPoints = serverPoints ?? (state.points - cost);
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

  /// Apply the AUTHORITATIVE result of any earn/redeem call.
  ///
  /// Prefers the server's `totalPoints` over local arithmetic so the balance
  /// never drifts (fixes optimistic-vs-server mismatch & cross-screen
  /// staleness), and captures the daily-cap flag so the UI can surface it.
  void applyEarnResult(Map<String, dynamic>? result) {
    if (_disposed || result == null) return;

    final serverTotal = (result['totalPoints'] as num?)?.toInt() ??
        (result['points'] as num?)?.toInt();

    final capReached = result['dailyCapReached'] == true ||
        result['reason'] == 'daily_cap_reached';
    final dailyEarned = (result['dailyEarned'] as num?)?.toInt();
    final dailyCap = (result['dailyCap'] as num?)?.toInt();

    if (serverTotal != null) {
      final (progress, ptsToNext, nextTier) =
          _computeTier(serverTotal, state.tier);
      state = state.copyWith(
        points: serverTotal,
        tierProgress: progress,
        pointsToNextTier: ptsToNext,
        nextTier: nextTier,
        dailyCapReached: capReached,
        dailyEarned: dailyEarned,
        dailyCap: dailyCap,
      );
    } else {
      state = state.copyWith(
        dailyCapReached: capReached,
        dailyEarned: dailyEarned,
        dailyCap: dailyCap,
      );
    }
  }

  /// Clear the one-shot daily-cap flag after the UI has shown it.
  void clearDailyCapFlag() {
    if (_disposed || !state.dailyCapReached) return;
    state = state.copyWith(dailyCapReached: false);
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

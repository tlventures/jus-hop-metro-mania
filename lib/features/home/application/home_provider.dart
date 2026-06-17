import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/backend_service.dart';
import 'streak_provider.dart';
import 'quest_provider.dart';
import '../../wallet/application/wallet_provider.dart';

// ---------------------------------------------------------------------------
// HomeData — the full aggregate response from GET /api/home
// ---------------------------------------------------------------------------

class HomeData {
  final Map<String, dynamic> profile;
  final Map<String, dynamic> streak;
  final List<Map<String, dynamic>> quests;
  final Map<String, dynamic> wallet;
  final List<Map<String, dynamic>> games;
  final List<Map<String, dynamic>> featuredVideos;

  const HomeData({
    required this.profile,
    required this.streak,
    required this.quests,
    required this.wallet,
    required this.games,
    required this.featuredVideos,
  });

  factory HomeData.fromJson(Map<String, dynamic> json) {
    List<Map<String, dynamic>> asMaps(dynamic raw) {
      if (raw == null) return [];
      return (raw as List<dynamic>)
          .whereType<Map<String, dynamic>>()
          .toList();
    }

    return HomeData(
      profile:       (json['profile'] as Map<String, dynamic>?) ?? {},
      streak:        (json['streak']  as Map<String, dynamic>?) ?? {},
      quests:        asMaps(json['quests']),
      wallet:        (json['wallet']  as Map<String, dynamic>?) ?? {},
      games:         asMaps(json['games']),
      featuredVideos: asMaps(json['featuredVideos']),
    );
  }
}

// ---------------------------------------------------------------------------
// HomeNotifier — single fetch, hydrates streak/quests/wallet on success
// ---------------------------------------------------------------------------

class HomeNotifier extends StateNotifier<AsyncValue<HomeData>> {
  final BackendService _backendService;
  final Ref _ref;
  bool _disposed = false;

  HomeNotifier(this._backendService, this._ref)
      : super(const AsyncValue.loading());

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> fetch() async {
    if (_disposed) return;
    // Keep the previous data visible while refreshing so the home doesn't blank
    // to a full-screen skeleton on every resume/refresh — only the very first
    // load (no previous value) shows the skeleton.
    state = const AsyncValue<HomeData>.loading().copyWithPrevious(state);
    try {
      final raw = await _backendService.getHomeData();
      if (_disposed) return;

      final home = HomeData.fromJson(raw);
      state = AsyncValue.data(home);

      // Hydrate streak notifier from the aggregate response
      _ref.read(streakProvider.notifier).hydrateFromHomeData(home.streak);

      // Hydrate quests notifier
      _ref.read(questsProvider.notifier).hydrateFromHomeData(home.quests);

      // Hydrate wallet summary (points + tier only; transactions still
      // loaded separately by the wallet tab when it opens)
      _ref.read(walletProvider.notifier).hydrateFromHomeData(home.wallet);

      // Auto-advance the daily streak so it tracks on app open (no manual tap).
      // If it lands, reflect the new points in the wallet immediately.
      final claimed = await _ref.read(streakProvider.notifier).autoClaimIfDue();
      if (claimed && !_disposed) {
        final pts = _ref.read(streakProvider).totalPoints;
        _ref.read(walletProvider.notifier).applyEarnResult({'totalPoints': pts});
      }
    } catch (e, st) {
      debugPrint('HomeNotifier.fetch error: $e');
      if (!_disposed) state = AsyncValue.error(e, st);
    }
  }

  /// Called after any earn/redeem to pull fresh home data. Refreshes in the
  /// background (keeps current data on screen) rather than blanking to a
  /// skeleton — the home may stay mounted under a pushed game route, so a lazy
  /// "reload on next open" would otherwise never fire.
  void invalidate() {
    if (!_disposed) fetch();
  }
}

final homeServiceProvider = Provider<BackendService>((ref) => BackendService());

final homeProvider =
    StateNotifierProvider<HomeNotifier, AsyncValue<HomeData>>((ref) {
  return HomeNotifier(ref.watch(homeServiceProvider), ref);
});

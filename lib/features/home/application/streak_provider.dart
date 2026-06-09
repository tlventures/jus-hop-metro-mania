import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/backend_service.dart';

class Streak {
  final int currentDay;
  final int longestStreak;
  final DateTime lastClaimedAt;
  final int totalPoints;

  Streak({
    required this.currentDay,
    required this.longestStreak,
    required this.lastClaimedAt,
    required this.totalPoints,
  });

  bool get canClaim {
    // Calendar-day based: claimable once per day. The backend is authoritative
    // (it enforces one claim per IST day); this just gates the auto-claim.
    final now = DateTime.now();
    final last = lastClaimedAt;
    return !(last.year == now.year && last.month == now.month && last.day == now.day);
  }

  int get pointsForClaim => currentDay * 5; // 5 pts × day number
}

class StreakNotifier extends StateNotifier<Streak> {
  final BackendService _backendService;
  bool _disposed = false;

  StreakNotifier(this._backendService)
      : super(
          Streak(
            currentDay: 0,
            longestStreak: 0,
            lastClaimedAt: DateTime(1970), // epoch = never claimed
            totalPoints: 0,
          ),
        );

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> fetchStreak() async {
    try {
      final data = await _backendService.getHomeData();
      if (_disposed) return;
      final streakData = data['streak'] as Map<String, dynamic>?;
      if (streakData != null) {
        state = Streak(
          currentDay: (streakData['currentDay'] as num?)?.toInt() ?? state.currentDay,
          longestStreak: (streakData['longestStreak'] as num?)?.toInt() ?? state.longestStreak,
          lastClaimedAt: streakData['lastClaimedAt'] != null
              ? DateTime.tryParse(streakData['lastClaimedAt'] as String) ?? state.lastClaimedAt
              : state.lastClaimedAt,
          totalPoints: (streakData['totalPoints'] as num?)?.toInt() ?? state.totalPoints,
        );
      }
    } catch (e) {
      debugPrint('StreakNotifier.fetchStreak error: $e');
    }
  }

  /// Hydrate from the /api/home aggregate — no extra network call.
  void hydrateFromHomeData(Map<String, dynamic> streakData) {
    if (_disposed) return;
    state = Streak(
      currentDay:    (streakData['currentDay']    as num?)?.toInt() ?? state.currentDay,
      longestStreak: (streakData['longestStreak'] as num?)?.toInt() ?? state.longestStreak,
      lastClaimedAt: streakData['lastClaimedAt'] != null
          ? DateTime.tryParse(streakData['lastClaimedAt'] as String) ?? state.lastClaimedAt
          : state.lastClaimedAt,
      totalPoints:   (streakData['totalPoints']   as num?)?.toInt() ?? state.totalPoints,
    );
  }

  /// Claim today's streak. Uses the server's authoritative response (handles
  /// increment vs. reset-on-missed-day). Returns true if a claim landed.
  Future<bool> claimStreak() async {
    try {
      final res = await _backendService.claimStreakBonus();
      if (_disposed) return false;
      final day = (res['streakDay'] as num?)?.toInt();
      if (day != null) {
        state = Streak(
          currentDay: day,
          longestStreak: (res['longestStreak'] as num?)?.toInt() ?? state.longestStreak,
          lastClaimedAt: DateTime.now(),
          totalPoints: (res['totalPoints'] as num?)?.toInt() ?? state.totalPoints,
        );
        return true;
      }
    } catch (e) {
      // 400 "already counted today" is the expected no-op when the streak was
      // already claimed within 24h — stay silent. Only log genuine failures.
      final msg = e.toString();
      if (!msg.contains('already counted') && !msg.contains('already claimed')) {
        debugPrint('StreakNotifier.claimStreak: $e');
      }
    }
    return false;
  }

  /// Auto-advance the streak on app open if a day is due (>24h since last
  /// claim). Makes the streak track automatically without a manual tap.
  Future<bool> autoClaimIfDue() async {
    if (_disposed || !state.canClaim) return false;
    return claimStreak();
  }

  void resetStreak() {
    state = Streak(
      currentDay: 1,
      longestStreak: state.longestStreak,
      lastClaimedAt: DateTime.now(),
      totalPoints: state.totalPoints,
    );
  }
}

final streakServiceProvider = Provider((ref) => BackendService());

final streakProvider = StateNotifierProvider<StreakNotifier, Streak>((ref) {
  final backendService = ref.watch(streakServiceProvider);
  return StreakNotifier(backendService);
});

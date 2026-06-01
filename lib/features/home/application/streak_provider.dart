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
    final now = DateTime.now();
    final lastClaim = lastClaimedAt;
    return now.difference(lastClaim).inHours >= 24;
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

  Future<void> claimStreak() async {
    try {
      await _backendService.claimStreakBonus();
    } catch (e) {
      debugPrint('StreakNotifier.claimStreak error: $e');
    }

    state = Streak(
      currentDay: state.currentDay + 1,
      longestStreak:
          state.currentDay + 1 > state.longestStreak ? state.currentDay + 1 : state.longestStreak,
      lastClaimedAt: DateTime.now(),
      totalPoints: state.totalPoints + state.pointsForClaim,
    );
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

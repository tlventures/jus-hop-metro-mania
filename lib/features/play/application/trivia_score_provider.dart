import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/backend_service.dart';

class TriviaRankSnapshot {
  final int? rank;
  final int score;
  final int personalRecord;
  final int bestToday;
  final int playerCount;
  final List<Map<String, dynamic>> topScores;

  const TriviaRankSnapshot({
    required this.rank,
    required this.score,
    required this.personalRecord,
    required this.bestToday,
    required this.playerCount,
    required this.topScores,
  });

  factory TriviaRankSnapshot.fromJson(Map<String, dynamic> json) {
    return TriviaRankSnapshot(
      rank: (json['rank'] as num?)?.toInt(),
      score: (json['score'] as num?)?.toInt() ?? 0,
      personalRecord: (json['personalRecord'] as num?)?.toInt() ?? 0,
      bestToday: (json['bestToday'] as num?)?.toInt() ?? 0,
      playerCount: (json['playerCount'] as num?)?.toInt() ?? 0,
      topScores:
          (json['topScores'] as List<dynamic>? ?? [])
              .map((item) => Map<String, dynamic>.from(item as Map))
              .toList(),
    );
  }
}

class TriviaScoreNotifier
    extends StateNotifier<AsyncValue<TriviaRankSnapshot>> {
  final BackendService _backend;

  TriviaScoreNotifier(this._backend) : super(const AsyncValue.loading());

  void replace(TriviaRankSnapshot snapshot) {
    state = AsyncValue.data(snapshot);
  }

  Future<void> load({String? cityId}) async {
    try {
      final data = await _backend.getTriviaRank(cityId: cityId);
      state = AsyncValue.data(TriviaRankSnapshot.fromJson(data));
    } catch (error, stackTrace) {
      debugPrint('TriviaScoreNotifier.load error: $error');
      state = AsyncValue.error(error, stackTrace);
    }
  }

  Future<void> submit({
    required int score,
    String? cityId,
    int? questionsAnswered,
    int? streak,
    int? timeSpent,
  }) async {
    try {
      final data = await _backend.submitTriviaScore(
        score: score,
        cityId: cityId,
        questionsAnswered: questionsAnswered,
        streak: streak,
        timeSpent: timeSpent,
      );
      state = AsyncValue.data(TriviaRankSnapshot.fromJson(data));
    } catch (error, stackTrace) {
      debugPrint('TriviaScoreNotifier.submit error: $error');
      state = AsyncValue.error(error, stackTrace);
    }
  }
}

final triviaScoreProvider =
    StateNotifierProvider<TriviaScoreNotifier, AsyncValue<TriviaRankSnapshot>>(
      (ref) => TriviaScoreNotifier(BackendService()),
    );

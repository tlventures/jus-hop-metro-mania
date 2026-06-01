import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/backend_service.dart';

class GameRecord {
  final String id;
  final String name;
  final String description;
  final int pointsPerRound;
  final String type;
  final int bestScore;
  final DateTime lastPlayedAt;
  final String icon;
  final String commuteLengthLabel;

  GameRecord({
    required this.id,
    required this.name,
    required this.description,
    required this.pointsPerRound,
    required this.type,
    required this.bestScore,
    required this.lastPlayedAt,
    required this.icon,
    this.commuteLengthLabel = '',
  });

  GameRecord copyWith({int? bestScore, DateTime? lastPlayedAt}) {
    return GameRecord(
      id: id,
      name: name,
      description: description,
      pointsPerRound: pointsPerRound,
      type: type,
      bestScore: bestScore ?? this.bestScore,
      lastPlayedAt: lastPlayedAt ?? this.lastPlayedAt,
      icon: icon,
      commuteLengthLabel: commuteLengthLabel,
    );
  }
}

class GamesNotifier extends StateNotifier<List<GameRecord>> {
  final BackendService _backendService;

  static final _catalog = [
    GameRecord(
      id: 'daily_spin',
      name: 'Daily Spin',
      description: 'Spin for random rewards',
      pointsPerRound: 50,
      type: 'spin',
      bestScore: 0,
      lastPlayedAt: DateTime(1970),
      icon: '🎡',
      commuteLengthLabel: '1-min ride',
    ),
    GameRecord(
      id: 'trivia',
      name: 'Metro Trivia',
      description: 'Test your metro knowledge',
      pointsPerRound: 10,
      type: 'quiz',
      bestScore: 0,
      lastPlayedAt: DateTime(1970),
      icon: '🧠',
      commuteLengthLabel: '5-min ride',
    ),
    GameRecord(
      id: 'sudoku',
      name: 'Sudoku',
      description: 'Classic puzzle game',
      pointsPerRound: 25,
      type: 'puzzle',
      bestScore: 0,
      lastPlayedAt: DateTime(1970),
      icon: '🔢',
      commuteLengthLabel: '10-min ride',
    ),
    GameRecord(
      id: 'word_puzzle',
      name: 'Word Puzzle',
      description: 'Unscramble station names',
      pointsPerRound: 10,
      type: 'word',
      bestScore: 0,
      lastPlayedAt: DateTime(1970),
      icon: '🔤',
      commuteLengthLabel: '3-min ride',
    ),
    GameRecord(
      id: 'city_explorer',
      name: 'City Explorer',
      description: 'Discover metro landmarks',
      pointsPerRound: 15,
      type: 'exploration',
      bestScore: 0,
      lastPlayedAt: DateTime(1970),
      icon: '🗺️',
      commuteLengthLabel: '15-min ride',
    ),
  ];

  GamesNotifier(this._backendService) : super(List.of(_catalog));

  Future<void> fetchScores() async {
    try {
      final data = await _backendService.getProfile();
      final raw = data['gameScores'] as Map<String, dynamic>?;
      if (raw == null) return;
      state =
          state.map((game) {
            final scores = raw[game.id] as Map<String, dynamic>?;
            if (scores == null) return game;
            return game.copyWith(
              bestScore: (scores['score'] as num?)?.toInt() ?? game.bestScore,
            );
          }).toList();
    } catch (e) {
      debugPrint('GamesNotifier.fetchScores error: $e');
    }
  }

  Future<Map<String, dynamic>?> updateGameScore(
    String gameId,
    int score, {
    String? cityId,
    int? questionsAnswered,
    int? streak,
    int timeSpent = 0,
  }) async {
    Map<String, dynamic>? result;
    try {
      result = await _backendService.completeGame(
        gameId: gameId,
        score: score,
        timeSpent: timeSpent,
        cityId: cityId,
        questionsAnswered: questionsAnswered,
        streak: streak,
      );
      // Game completed — also mark the play_game daily quest done
      try {
        await _backendService.completeQuest('play_game');
      } catch (_) {}
    } catch (e) {
      debugPrint('GamesNotifier.updateGameScore error: $e');
    }

    state =
        state.map((game) {
          if (game.id == gameId) {
            return game.copyWith(
              bestScore: score > game.bestScore ? score : game.bestScore,
              lastPlayedAt: DateTime.now(),
            );
          }
          return game;
        }).toList();
    return result;
  }

  int get totalGamesPlayed => state.length;

  int get totalBestScore => state.fold(0, (sum, game) => sum + game.bestScore);
}

final backendServiceProvider = Provider((ref) => BackendService());

final gamesProvider = StateNotifierProvider<GamesNotifier, List<GameRecord>>((
  ref,
) {
  final backendService = ref.watch(backendServiceProvider);
  return GamesNotifier(backendService);
});

final totalGameScoreProvider = Provider<int>((ref) {
  final games = ref.watch(gamesProvider);
  return games.fold(0, (sum, game) => sum + game.bestScore);
});

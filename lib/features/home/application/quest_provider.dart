import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../services/backend_service.dart';

enum QuestType { rideStarted, playGame, watchVideo, readArticle, stationQuiz, checkPassport }

class Quest {
  final String id;
  final String title;
  final String description;
  final int points;
  final QuestType type;
  final bool isCompleted;
  final DateTime resetAt;

  const Quest({
    required this.id,
    required this.title,
    required this.description,
    required this.points,
    required this.type,
    required this.isCompleted,
    required this.resetAt,
  });

  bool get isAvailable => DateTime.now().isBefore(resetAt);

  Quest copyWith({bool? isCompleted}) => Quest(
    id: id,
    title: title,
    description: description,
    points: points,
    type: type,
    isCompleted: isCompleted ?? this.isCompleted,
    resetAt: resetAt,
  );

  static QuestType _parseType(String raw) {
    switch (raw) {
      case 'ride_started':           return QuestType.rideStarted;
      case 'game_completed':         return QuestType.playGame;
      case 'article_read':           return QuestType.readArticle;
      case 'station_quiz_completed': return QuestType.stationQuiz;
      case 'passport_viewed':        return QuestType.checkPassport;
      default:                       return QuestType.playGame;
    }
  }

  factory Quest.fromJson(Map<String, dynamic> json) {
    return Quest(
      id: json['id'] as String,
      title: json['title'] as String,
      description: json['description'] as String,
      points: (json['points'] as num).toInt(),
      type: _parseType(json['type'] as String? ?? ''),
      isCompleted: json['isCompleted'] as bool? ?? false,
      resetAt: DateTime.tryParse(json['resetAt'] as String? ?? '') ??
          DateTime.now().add(const Duration(hours: 24)),
    );
  }

  // Fallback quests shown before network loads
  static List<Quest> get defaults {
    final midnight = DateTime.now().copyWith(hour: 23, minute: 59, second: 59);
    return [
      Quest(id: 'start_ride',   title: 'Start Ride Mode',    description: 'Begin a metro commute session', points: 30, type: QuestType.rideStarted,   isCompleted: false, resetAt: midnight),
      Quest(id: 'play_game',    title: 'Play a game',         description: 'Complete any game',            points: 20, type: QuestType.playGame,        isCompleted: false, resetAt: midnight),
      Quest(id: 'read_article', title: 'Read an article',     description: 'Read any article in Learn',    points: 15, type: QuestType.readArticle,     isCompleted: false, resetAt: midnight),
    ];
  }
}

class QuestsNotifier extends StateNotifier<List<Quest>> {
  final BackendService _backendService;

  QuestsNotifier(this._backendService) : super(Quest.defaults);

  /// Hydrate from the /api/home aggregate — no extra network call.
  void hydrateFromHomeData(List<Map<String, dynamic>> questsJson) {
    if (!mounted) return;
    if (questsJson.isNotEmpty) {
      state = questsJson.map((q) => Quest.fromJson(q)).toList();
    }
  }

  Future<void> fetchQuests() async {
    try {
      final data = await _backendService.getQuestsToday();
      if (!mounted) return;
      final questsJson = data['quests'] as List<dynamic>? ?? [];
      if (questsJson.isNotEmpty) {
        state = questsJson
            .map((q) => Quest.fromJson(q as Map<String, dynamic>))
            .toList();
      }
    } catch (e) {
      debugPrint('QuestsNotifier.fetchQuests error: $e');
    }
  }

  // Server-authoritative: only mark complete once backend confirms.
  // Returns true if the quest was accepted, false if already done or rejected.
  Future<bool> completeQuest(String questId) async {
    try {
      await _backendService.completeQuest(questId);
      if (!mounted) return false;
      state = state.map((q) => q.id == questId ? q.copyWith(isCompleted: true) : q).toList();
      return true;
    } catch (e) {
      debugPrint('QuestsNotifier.completeQuest error: $e');
      return false;
    }
  }

  int get completedCount => state.where((q) => q.isCompleted).length;
  int get totalPoints => state.fold(0, (sum, q) => sum + (q.isCompleted ? q.points : 0));
}

final questServiceProvider = Provider((ref) => BackendService());

final questsProvider = StateNotifierProvider<QuestsNotifier, List<Quest>>((ref) {
  return QuestsNotifier(ref.watch(questServiceProvider));
});

final completedQuestsProvider = Provider<int>((ref) {
  return ref.watch(questsProvider).where((q) => q.isCompleted).length;
});

final questPointsProvider = Provider<int>((ref) {
  return ref.watch(questsProvider).fold(0, (sum, q) => sum + (q.isCompleted ? q.points : 0));
});

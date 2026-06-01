class ActivityEvent {
  final String type;
  final String? entityId;
  final Map<String, dynamic>? metadata;

  const ActivityEvent({required this.type, this.entityId, this.metadata});

  Map<String, dynamic> toJson() => {
    'type': type,
    if (entityId != null) 'entityId': entityId,
    if (metadata != null) 'metadata': metadata,
  };

  // Predefined type constants
  static const String gameCompleted = 'game_completed';
  static const String questCompleted = 'quest_completed';
  static const String articleRead = 'article_read';
  static const String surveySubmitted = 'survey_submitted';
  static const String storyCompleted = 'story_completed';
  static const String rideStarted = 'ride_started';
  static const String rideCompleted = 'ride_completed';
  static const String stampClaimed = 'stamp_claimed';
  static const String stationQuizCompleted = 'station_quiz_completed';
  static const String passportViewed = 'passport_viewed';
}

class ActivityEventResult {
  final String transactionId;
  final int pointsAwarded;
  final int totalPoints;
  final bool dailyCapReached;
  final int dailyEarned;
  final int dailyCap;

  const ActivityEventResult({
    required this.transactionId,
    required this.pointsAwarded,
    required this.totalPoints,
    required this.dailyCapReached,
    required this.dailyEarned,
    required this.dailyCap,
  });

  factory ActivityEventResult.fromJson(Map<String, dynamic> json) {
    return ActivityEventResult(
      transactionId: json['transactionId'] as String? ?? '',
      pointsAwarded: (json['pointsAwarded'] as num?)?.toInt() ?? 0,
      totalPoints: (json['totalPoints'] as num?)?.toInt() ?? 0,
      dailyCapReached: json['reason'] == 'daily_cap_reached',
      dailyEarned: (json['dailyEarned'] as num?)?.toInt() ?? 0,
      dailyCap: (json['dailyCap'] as num?)?.toInt() ?? 500,
    );
  }
}

class WalletTransaction {
  final String id;
  final String type;
  final String description;
  final int pointsAwarded;
  final DateTime createdAt;

  const WalletTransaction({
    required this.id,
    required this.type,
    required this.description,
    required this.pointsAwarded,
    required this.createdAt,
  });

  factory WalletTransaction.fromJson(Map<String, dynamic> json) {
    return WalletTransaction(
      id: json['id'] as String? ?? '',
      type: json['type'] as String? ?? '',
      description: json['description'] as String? ?? '',
      pointsAwarded: (json['pointsAwarded'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime.now(),
    );
  }
}

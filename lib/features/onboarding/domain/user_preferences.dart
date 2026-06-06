/// Persisted user interest / preference selections collected during the
/// post-signup interests flow.
class UserPreferences {
  /// Content types the user enjoys (keys from [ContentType]).
  final Set<String> contentTypes;

  /// Game genres (keys from [GameGenre]). Non-empty only when 'games' is in
  /// [contentTypes].
  final Set<String> gameGenres;

  /// Topic / interest tags (keys from [ContentTopic]).
  final Set<String> topics;

  const UserPreferences({
    this.contentTypes = const {},
    this.gameGenres = const {},
    this.topics = const {},
  });

  UserPreferences copyWith({
    Set<String>? contentTypes,
    Set<String>? gameGenres,
    Set<String>? topics,
  }) =>
      UserPreferences(
        contentTypes: contentTypes ?? this.contentTypes,
        gameGenres: gameGenres ?? this.gameGenres,
        topics: topics ?? this.topics,
      );

  /// Serialize to a plain map for SharedPreferences / backend.
  Map<String, dynamic> toJson() => {
        'contentTypes': contentTypes.toList(),
        'gameGenres': gameGenres.toList(),
        'topics': topics.toList(),
      };

  factory UserPreferences.fromJson(Map<String, dynamic> json) =>
      UserPreferences(
        contentTypes: Set<String>.from(
            (json['contentTypes'] as List?)?.cast<String>() ?? []),
        gameGenres: Set<String>.from(
            (json['gameGenres'] as List?)?.cast<String>() ?? []),
        topics: Set<String>.from(
            (json['topics'] as List?)?.cast<String>() ?? []),
      );

  bool get isEmpty =>
      contentTypes.isEmpty && gameGenres.isEmpty && topics.isEmpty;
}

// ─── Catalogue entries ────────────────────────────────────────────────────────

class InterestOption {
  final String key;
  final String emoji;
  final String label;
  final String description;
  const InterestOption({
    required this.key,
    required this.emoji,
    required this.label,
    required this.description,
  });
}

/// Step 1 – what kind of content?
class ContentType {
  static const audio = InterestOption(
    key: 'audio',
    emoji: '🎧',
    label: 'Audio Stories',
    description: 'Listen while you commute',
  );
  static const video = InterestOption(
    key: 'video',
    emoji: '🎬',
    label: 'Video Stories',
    description: 'Short clips on the go',
  );
  static const news = InterestOption(
    key: 'news',
    emoji: '📰',
    label: 'News Updates',
    description: 'Stay in the know',
  );
  static const games = InterestOption(
    key: 'games',
    emoji: '🎮',
    label: 'Games',
    description: 'Play & earn points',
  );
  static const reading = InterestOption(
    key: 'reading',
    emoji: '📖',
    label: 'Reading',
    description: 'Articles & long reads',
  );

  static const all = [audio, video, news, games, reading];
}

/// Step 2 – game genres (shown only when 'games' is selected).
class GameGenre {
  static const trivia = InterestOption(
    key: 'trivia',
    emoji: '🧠',
    label: 'Trivia & Quiz',
    description: 'Test your knowledge',
  );
  static const puzzle = InterestOption(
    key: 'puzzle',
    emoji: '🔤',
    label: 'Word & Puzzles',
    description: 'Sudoku, word games',
  );
  static const explorer = InterestOption(
    key: 'explorer',
    emoji: '🗺️',
    label: 'City Explorer',
    description: 'Discover your city',
  );
  static const spin = InterestOption(
    key: 'spin',
    emoji: '🎰',
    label: 'Luck & Spin',
    description: 'Daily spin rewards',
  );

  static const all = [trivia, puzzle, explorer, spin];
}

/// Step 3 – content topics.
class ContentTopic {
  static const city = InterestOption(
    key: 'city',
    emoji: '🏙️',
    label: 'City & Metro Life',
    description: 'Local stories & tips',
  );
  static const travel = InterestOption(
    key: 'travel',
    emoji: '✈️',
    label: 'Travel & Culture',
    description: 'Explore beyond your city',
  );
  static const tech = InterestOption(
    key: 'tech',
    emoji: '💡',
    label: 'Tech & Innovation',
    description: 'What\'s shaping tomorrow',
  );
  static const entertainment = InterestOption(
    key: 'entertainment',
    emoji: '🎭',
    label: 'Entertainment',
    description: 'Movies, music, art',
  );
  static const sports = InterestOption(
    key: 'sports',
    emoji: '⚽',
    label: 'Sports',
    description: 'Scores & highlights',
  );
  static const food = InterestOption(
    key: 'food',
    emoji: '🍕',
    label: 'Food & Lifestyle',
    description: 'Recipes, wellness & more',
  );
  static const finance = InterestOption(
    key: 'finance',
    emoji: '💰',
    label: 'Finance & Career',
    description: 'Money tips & growth',
  );
  static const health = InterestOption(
    key: 'health',
    emoji: '🏃',
    label: 'Health & Fitness',
    description: 'Mind and body tips',
  );

  static const all = [
    city, travel, tech, entertainment, sports, food, finance, health
  ];
}

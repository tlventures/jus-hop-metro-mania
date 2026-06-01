// lib/core/city/content_pack_models.dart
//
// Data models for city-specific content packs (trivia, landmarks, stamps,
// sudoku icons, etc.). All localized — call `.localized(locale)` to resolve.

// ── Trivia ───────────────────────────────────────────────────────────────────

class TriviaQuestion {
  final String id;
  final Map<String, String> question;
  final Map<String, List<String>> options;
  final int correctIndex;
  final Map<String, String> explanation;

  const TriviaQuestion({
    required this.id,
    required this.question,
    required this.options,
    required this.correctIndex,
    this.explanation = const {},
  });

  factory TriviaQuestion.fromJson(Map<String, dynamic> j) {
    final rawOpts = j['options'] as Map? ?? {};
    return TriviaQuestion(
      id: j['id'] as String,
      question:    Map<String, String>.from(j['question'] as Map),
      options:     rawOpts.map((k, v) =>
                       MapEntry(k as String, List<String>.from(v as List))),
      correctIndex: j['correctIndex'] as int,
      explanation:  j['explanation'] != null
          ? Map<String, String>.from(j['explanation'] as Map)
          : const {},
    );
  }

  String localizedQuestion(String locale) =>
      question[locale] ?? question['en'] ?? '';

  List<String> localizedOptions(String locale) =>
      options[locale] ?? options['en'] ?? [];

  String localizedExplanation(String locale) =>
      explanation[locale] ?? explanation['en'] ?? '';
}

class TriviaCategory {
  final String id;
  final Map<String, String> name;
  final List<TriviaQuestion> questions;

  const TriviaCategory({required this.id, required this.name, required this.questions});

  factory TriviaCategory.fromJson(Map<String, dynamic> j) => TriviaCategory(
        id: j['id'] as String,
        name: Map<String, String>.from(j['name'] as Map),
        questions: (j['questions'] as List? ?? [])
            .map((q) => TriviaQuestion.fromJson(Map<String, dynamic>.from(q as Map)))
            .toList(),
      );

  String localizedName(String locale) => name[locale] ?? name['en'] ?? id;
}

class TriviaPack {
  final String cityId;
  final String defaultLocale;
  final List<TriviaCategory> categories;

  const TriviaPack({
    required this.cityId,
    required this.defaultLocale,
    required this.categories,
  });

  factory TriviaPack.fromJson(Map<String, dynamic> j) => TriviaPack(
        cityId:        j['cityId']        as String? ?? '',
        defaultLocale: j['defaultLocale'] as String? ?? 'en',
        categories: (j['categories'] as List? ?? [])
            .map((c) => TriviaCategory.fromJson(Map<String, dynamic>.from(c as Map)))
            .toList(),
      );

  /// All questions flattened, in deterministic order.
  List<TriviaQuestion> get allQuestions =>
      categories.expand((c) => c.questions).toList();

  /// Pick `count` random questions across all categories.
  List<TriviaQuestion> randomSample(int count, {int? seed}) {
    final all = List<TriviaQuestion>.from(allQuestions);
    all.shuffle();
    return all.take(count).toList();
  }

  bool get isEmpty => categories.isEmpty;
}

// ── Landmarks ────────────────────────────────────────────────────────────────

class CityLandmark {
  final String id;
  final Map<String, String> name;
  final String category;
  final double lat;
  final double lng;
  final String icon;
  final Map<String, String> description;
  final String? nearestStationId;

  const CityLandmark({
    required this.id,
    required this.name,
    required this.category,
    required this.lat,
    required this.lng,
    required this.icon,
    required this.description,
    this.nearestStationId,
  });

  factory CityLandmark.fromJson(Map<String, dynamic> j) => CityLandmark(
        id:               j['id']       as String,
        name:             Map<String, String>.from(j['name'] as Map),
        category:         j['category'] as String? ?? 'general',
        lat:              (j['lat'] as num).toDouble(),
        lng:              (j['lng'] as num).toDouble(),
        icon:             j['icon']     as String? ?? '📍',
        description:      Map<String, String>.from(j['description'] as Map? ?? {}),
        nearestStationId: j['nearestStationId'] as String?,
      );

  String localizedName(String locale) =>
      name[locale] ?? name['en'] ?? id;

  String localizedDescription(String locale) =>
      description[locale] ?? description['en'] ?? '';
}

class LandmarksPack {
  final String cityId;
  final List<CityLandmark> landmarks;

  const LandmarksPack({required this.cityId, required this.landmarks});

  factory LandmarksPack.fromJson(Map<String, dynamic> j) => LandmarksPack(
        cityId:    j['cityId'] as String? ?? '',
        landmarks: (j['landmarks'] as List? ?? [])
            .map((l) => CityLandmark.fromJson(Map<String, dynamic>.from(l as Map)))
            .toList(),
      );

  bool get isEmpty => landmarks.isEmpty;
}

// ── Stamps ───────────────────────────────────────────────────────────────────

enum StampRarity { common, rare, legendary }

StampRarity _parseRarity(String? s) => switch (s) {
      'rare'      => StampRarity.rare,
      'legendary' => StampRarity.legendary,
      _           => StampRarity.common,
    };

class CityStamp {
  final String id;
  final Map<String, String> name;
  final StampRarity rarity;
  final String icon;
  final Map<String, dynamic> unlock; // { type, landmarkId | stationId | festivalId }

  const CityStamp({
    required this.id,
    required this.name,
    required this.rarity,
    required this.icon,
    required this.unlock,
  });

  factory CityStamp.fromJson(Map<String, dynamic> j) => CityStamp(
        id:     j['id']    as String,
        name:   Map<String, String>.from(j['name'] as Map),
        rarity: _parseRarity(j['rarity'] as String?),
        icon:   j['icon']  as String? ?? '🏅',
        unlock: Map<String, dynamic>.from(j['unlock'] as Map? ?? {}),
      );

  String localizedName(String locale) =>
      name[locale] ?? name['en'] ?? id;
}

class StampCollection {
  final String id;
  final Map<String, String> name;
  final List<CityStamp> stamps;

  const StampCollection({required this.id, required this.name, required this.stamps});

  factory StampCollection.fromJson(Map<String, dynamic> j) => StampCollection(
        id:     j['id']   as String,
        name:   Map<String, String>.from(j['name'] as Map),
        stamps: (j['stamps'] as List? ?? [])
            .map((s) => CityStamp.fromJson(Map<String, dynamic>.from(s as Map)))
            .toList(),
      );

  String localizedName(String locale) => name[locale] ?? name['en'] ?? id;
}

class StampsPack {
  final String cityId;
  final List<StampCollection> collections;

  const StampsPack({required this.cityId, required this.collections});

  factory StampsPack.fromJson(Map<String, dynamic> j) => StampsPack(
        cityId:      j['cityId'] as String? ?? '',
        collections: (j['collections'] as List? ?? [])
            .map((c) => StampCollection.fromJson(Map<String, dynamic>.from(c as Map)))
            .toList(),
      );

  int get totalStamps => collections.fold(0, (sum, c) => sum + c.stamps.length);
  bool get isEmpty => collections.isEmpty;
}

// ── Sudoku icons ─────────────────────────────────────────────────────────────

class SudokuIconPack {
  final String cityId;
  final Map<String, String> title;
  final Map<String, String> subtitle;
  final List<String> icons;                  // exactly 9
  final Map<String, String> iconLabels;      // emoji → English label

  const SudokuIconPack({
    required this.cityId,
    required this.title,
    required this.subtitle,
    required this.icons,
    required this.iconLabels,
  });

  factory SudokuIconPack.fromJson(Map<String, dynamic> j) => SudokuIconPack(
        cityId:     j['cityId'] as String? ?? '',
        title:      Map<String, String>.from(j['title']    as Map? ?? {}),
        subtitle:   Map<String, String>.from(j['subtitle'] as Map? ?? {}),
        icons:      List<String>.from(j['icons']           as List? ?? []),
        iconLabels: Map<String, String>.from(j['iconLabels'] as Map? ?? {}),
      );

  String localizedTitle(String locale) =>
      title[locale] ?? title['en'] ?? 'Sudoku';

  String localizedSubtitle(String locale) =>
      subtitle[locale] ?? subtitle['en'] ?? '';

  bool get isValid => icons.length == 9;
}

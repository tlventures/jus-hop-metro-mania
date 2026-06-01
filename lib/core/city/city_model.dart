// lib/core/city/city_model.dart
//
// First-class City entity. Every city carries its own branding, greetings,
// lines, fare grammar, and festival windows. Nothing assumes Hyderabad.

import '../../models/metro_station.dart';

class CityLine {
  final String id;
  final Map<String, String> name; // { "en": "Red Line", "te": "ఎరుపు రేఖ" }
  final String color; // hex e.g. "#E1252B"

  const CityLine({required this.id, required this.name, required this.color});

  factory CityLine.fromJson(Map<String, dynamic> j) => CityLine(
    id: j['id'] as String,
    name: Map<String, String>.from(j['name'] as Map),
    color: j['color'] as String,
  );

  /// Resolve a display name for the given locale, falling back to English.
  String localeName(String locale) => name[locale] ?? name['en'] ?? id;

  /// Parse hex color to Flutter int.
  int get colorValue {
    final hex = color.replaceAll('#', '');
    return int.parse('FF$hex', radix: 16);
  }
}

class CityBrand {
  final String primary;
  final String accent;
  final String surfaceVariant;
  final String skylineAsset;
  final String iconStamp;

  const CityBrand({
    required this.primary,
    required this.accent,
    required this.surfaceVariant,
    required this.skylineAsset,
    required this.iconStamp,
  });

  factory CityBrand.fromJson(Map<String, dynamic> j) => CityBrand(
    primary: j['primary'] as String? ?? '#4F46E5',
    accent: j['accent'] as String? ?? '#F59E0B',
    surfaceVariant: j['surfaceVariant'] as String? ?? '#F5F3FF',
    skylineAsset: j['skylineAsset'] as String? ?? '',
    iconStamp: j['iconStamp'] as String? ?? '',
  );

  int get primaryValue => _hexToInt(primary);
  int get accentValue => _hexToInt(accent);
  int get surfaceVariantValue => _hexToInt(surfaceVariant);

  static int _hexToInt(String hex) =>
      int.parse('FF${hex.replaceAll('#', '')}', radix: 16);
}

class CityGreetings {
  final Map<String, String> morning;
  final Map<String, String> afternoon;
  final Map<String, String> evening;

  const CityGreetings({
    required this.morning,
    required this.afternoon,
    required this.evening,
  });

  factory CityGreetings.fromJson(Map<String, dynamic> j) => CityGreetings(
    morning: Map<String, String>.from(j['morning'] as Map? ?? {}),
    afternoon: Map<String, String>.from(j['afternoon'] as Map? ?? {}),
    evening: Map<String, String>.from(j['evening'] as Map? ?? {}),
  );

  String greetingFor(String locale) {
    final hour = DateTime.now().hour;
    final bank = hour < 12 ? morning : (hour < 17 ? afternoon : evening);
    return bank[locale] ?? bank['en'] ?? 'Hello';
  }
}

class CityPhrases {
  final Map<String, String> rideComplete;
  final Map<String, String> streakCheer;
  final Map<String, String> loadingLine;

  const CityPhrases({
    required this.rideComplete,
    required this.streakCheer,
    required this.loadingLine,
  });

  factory CityPhrases.fromJson(Map<String, dynamic> j) => CityPhrases(
    rideComplete: Map<String, String>.from(j['rideComplete'] as Map? ?? {}),
    streakCheer: Map<String, String>.from(j['streakCheer'] as Map? ?? {}),
    loadingLine: Map<String, String>.from(j['loadingLine'] as Map? ?? {}),
  );

  String phrase(String key, String locale) {
    final bank = switch (key) {
      'rideComplete' => rideComplete,
      'streakCheer' => streakCheer,
      'loadingLine' => loadingLine,
      _ => <String, String>{},
    };
    return bank[locale] ?? bank['en'] ?? '';
  }
}

class FestivalWindow {
  final String id;
  final String startMMDD; // "07-14"
  final String endMMDD;
  final String themeId;

  const FestivalWindow({
    required this.id,
    required this.startMMDD,
    required this.endMMDD,
    required this.themeId,
  });

  factory FestivalWindow.fromJson(Map<String, dynamic> j) => FestivalWindow(
    id: j['id'] as String,
    startMMDD: j['startMMDD'] as String,
    endMMDD: j['endMMDD'] as String,
    themeId: j['themeId'] as String,
  );

  bool isActiveOn(DateTime date) {
    final mmdd =
        '${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    // Simple string comparison works for same-year windows; cross-year windows handled below
    if (startMMDD.compareTo(endMMDD) <= 0) {
      return mmdd.compareTo(startMMDD) >= 0 && mmdd.compareTo(endMMDD) <= 0;
    } else {
      // e.g. Dec 15 – Jan 13
      return mmdd.compareTo(startMMDD) >= 0 || mmdd.compareTo(endMMDD) <= 0;
    }
  }
}

class CitySignature {
  final List<String> food;
  final List<String> landmarks;
  final String identity;

  const CitySignature({
    required this.food,
    required this.landmarks,
    required this.identity,
  });

  factory CitySignature.fromJson(Map<String, dynamic> j) => CitySignature(
    food: List<String>.from(j['food'] as List? ?? []),
    landmarks: List<String>.from(j['landmarks'] as List? ?? []),
    identity: j['identity'] as String? ?? '',
  );
}

enum CityStatus { live, beta, waitlist, unknown }

/// The complete city entity — everything a screen needs to render city-aware UI.
class City {
  final String id;
  final Map<String, String> name; // { "en": "Hyderabad", "te": "హైదరాబాద్" }
  final Map<String, dynamic>
  operator_; // { "id": "hmrl", "name": "...", "shortName": "..." }
  final String country;
  final String timezone;
  final List<String> primaryLocales;
  final String defaultLocale;
  final List<CityLine> lines;
  final CityBrand brand;
  final CityGreetings greetings;
  final CityPhrases phrases;
  final List<FestivalWindow> festivalWindows;
  final CitySignature signature;
  final CityStatus status;
  final List<MetroStation> stations;

  const City({
    required this.id,
    required this.name,
    required this.operator_,
    required this.country,
    required this.timezone,
    required this.primaryLocales,
    required this.defaultLocale,
    required this.lines,
    required this.brand,
    required this.greetings,
    required this.phrases,
    required this.festivalWindows,
    required this.signature,
    required this.status,
    this.stations = const [],
  });

  factory City.fromJson(Map<String, dynamic> j) => City(
    id: j['id'] as String,
    name: Map<String, String>.from(j['name'] as Map),
    operator_: Map<String, dynamic>.from(j['operator'] as Map? ?? {}),
    country: j['country'] as String? ?? 'IN',
    timezone: j['timezone'] as String? ?? 'Asia/Kolkata',
    primaryLocales: List<String>.from(j['primaryLocales'] as List? ?? ['en']),
    defaultLocale: j['defaultLocale'] as String? ?? 'en',
    lines:
        (j['lines'] as List? ?? [])
            .map((l) => CityLine.fromJson(Map<String, dynamic>.from(l as Map)))
            .toList(),
    brand: CityBrand.fromJson(
      Map<String, dynamic>.from(j['brand'] as Map? ?? {}),
    ),
    greetings: CityGreetings.fromJson(
      Map<String, dynamic>.from(j['greetings'] as Map? ?? {}),
    ),
    phrases: CityPhrases.fromJson(
      Map<String, dynamic>.from(j['phrases'] as Map? ?? {}),
    ),
    festivalWindows:
        (j['festivalWindows'] as List? ?? [])
            .map(
              (fw) =>
                  FestivalWindow.fromJson(Map<String, dynamic>.from(fw as Map)),
            )
            .toList(),
    signature: CitySignature.fromJson(
      Map<String, dynamic>.from(j['signature'] as Map? ?? {}),
    ),
    status: _parseStatus(j['status'] as String? ?? 'unknown'),
    stations:
        (j['stations'] as List? ?? [])
            .map(
              (station) => MetroStation.fromJson(
                Map<String, dynamic>.from(station as Map),
              ),
            )
            .toList(),
  );

  static CityStatus _parseStatus(String s) => switch (s) {
    'live' => CityStatus.live,
    'beta' => CityStatus.beta,
    'waitlist' => CityStatus.waitlist,
    _ => CityStatus.unknown,
  };

  /// Localized display name, falling back to English.
  String displayName(String locale) => name[locale] ?? name['en'] ?? id;

  /// Operator short name.
  String get operatorShortName =>
      operator_['shortName'] as String? ?? operator_['name'] as String? ?? '';

  /// Active festival window for today, if any.
  FestivalWindow? get activeFestival {
    final today = DateTime.now();
    for (final fw in festivalWindows) {
      if (fw.isActiveOn(today)) return fw;
    }
    return null;
  }

  /// Line by id.
  CityLine? lineById(String lineId) {
    for (final l in lines) {
      if (l.id == lineId) return l;
    }
    return null;
  }
}

/// Lightweight summary used for city-picker lists (avoids transferring all brand/phrase data).
class CitySummary {
  final String id;
  final Map<String, String> name;
  final CityStatus status;
  final String operatorShortName;

  const CitySummary({
    required this.id,
    required this.name,
    required this.status,
    required this.operatorShortName,
  });

  factory CitySummary.fromJson(Map<String, dynamic> j) => CitySummary(
    id: j['id'] as String,
    name: Map<String, String>.from(j['name'] as Map),
    status: City._parseStatus(j['status'] as String? ?? 'unknown'),
    operatorShortName: (j['operator'] as Map?)?['shortName'] as String? ?? '',
  );

  String displayName(String locale) => name[locale] ?? name['en'] ?? id;
}

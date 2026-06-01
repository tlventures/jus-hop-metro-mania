// lib/models/metro_station.dart
//
// Multi-city aware station model.
//
// New stations from the v2 API use namespaced ids (e.g. "hyd_red_11") and
// carry a `names` locale map plus `lineIds` array.
//
// Old Hyderabad-only stations from the legacy API carry plain numeric ids,
// `name` string, and `line` string. Both formats are handled in fromJson so
// nothing breaks during the migration window.

class MetroStation {
  /// Namespaced unique id (e.g. "hyd_red_11") or legacy numeric string ("11").
  final String id;

  /// Legacy numeric id kept for backward-compat one release cycle.
  final String? legacyId;

  /// City this station belongs to (e.g. "hyd", "del", "blr", "che").
  final String cityId;

  /// Multilingual names. Use [localeName] to resolve for a locale.
  final Map<String, String> names;

  /// All line ids served here; interchange stations have > 1.
  final List<String> lineIds;

  /// IATA-style station code (e.g. "AMP").
  final String? code;

  /// Facilities: "parking", "wheelchair", "feeder_bus".
  final List<String> facilities;

  // ── Backward-compat getters used by existing screens ───────────────────────

  /// English station name (or first name available).
  String get name => names['en'] ?? names.values.firstOrNull ?? id;

  /// Primary line id (first in lineIds). Legacy screens expect a string.
  String get line => lineIds.isNotEmpty ? lineIds.first : '';

  // ── Location / runtime ─────────────────────────────────────────────────────

  /// Distance from current user position in km (set at runtime, not persisted).
  final double distance;
  final double latitude;
  final double longitude;
  final String? walkingTime;
  final String? arrivalTime;
  final String? departureTime;
  final Map<String, dynamic>? additionalInfo;

  MetroStation({
    required this.id,
    this.legacyId,
    this.cityId = 'hyd',
    Map<String, String>? names,
    String? name,              // legacy single-locale name — stored in names['en']
    List<String>? lineIds,
    String? line,              // legacy single line string — stored in lineIds[0]
    this.code,
    List<String>? facilities,
    required this.distance,
    this.latitude = 0.0,
    this.longitude = 0.0,
    this.walkingTime,
    this.arrivalTime,
    this.departureTime,
    this.additionalInfo,
  })  : names    = names    ?? (name    != null ? {'en': name}    : {}),
        lineIds   = lineIds  ?? (line    != null ? [line]          : []),
        facilities = facilities ?? [];

  /// Resolve the station name for a given locale, falling back to English.
  String localeName(String locale) => names[locale] ?? names['en'] ?? id;

  MetroStation copyWith({
    String? id,
    String? legacyId,
    String? cityId,
    Map<String, String>? names,
    List<String>? lineIds,
    String? code,
    List<String>? facilities,
    double? distance,
    double? latitude,
    double? longitude,
    String? walkingTime,
    String? arrivalTime,
    String? departureTime,
    Map<String, dynamic>? additionalInfo,
  }) {
    return MetroStation(
      id:            id            ?? this.id,
      legacyId:      legacyId      ?? this.legacyId,
      cityId:        cityId        ?? this.cityId,
      names:         names         ?? this.names,
      lineIds:       lineIds       ?? this.lineIds,
      code:          code          ?? this.code,
      facilities:    facilities    ?? this.facilities,
      distance:      distance      ?? this.distance,
      latitude:      latitude      ?? this.latitude,
      longitude:     longitude     ?? this.longitude,
      walkingTime:   walkingTime   ?? this.walkingTime,
      arrivalTime:   arrivalTime   ?? this.arrivalTime,
      departureTime: departureTime ?? this.departureTime,
      additionalInfo:additionalInfo?? this.additionalInfo,
    );
  }

  Map<String, dynamic> toJson() => {
        'id':            id,
        'legacyId':      legacyId,
        'cityId':        cityId,
        'names':         names,
        'lineIds':       lineIds,
        'code':          code,
        'facilities':    facilities,
        'distance':      distance,
        'latitude':      latitude,
        'longitude':     longitude,
        'walkingTime':   walkingTime,
        'arrivalTime':   arrivalTime,
        'departureTime': departureTime,
        'additionalInfo':additionalInfo,
      };

  factory MetroStation.fromJson(Map<String, dynamic> json) {
    // ── New v2 format: has `names` map and `lineIds` array ──────────────────
    if (json['names'] != null && json['names'] is Map) {
      return MetroStation(
        id:            json['id']        as String,
        legacyId:      json['legacyId']  as String?,
        cityId:        json['cityId']    as String? ?? 'hyd',
        names:         Map<String, String>.from(json['names'] as Map),
        lineIds:       json['lineIds'] != null
            ? List<String>.from(json['lineIds'] as List)
            : [],
        code:          json['code']      as String?,
        facilities:    json['facilities'] != null
            ? List<String>.from(json['facilities'] as List)
            : [],
        distance:      (json['distance'] as num?)?.toDouble()  ?? 0.0,
        latitude:      (json['lat']      as num?)?.toDouble()  ??
                       (json['latitude'] as num?)?.toDouble()  ?? 0.0,
        longitude:     (json['lng']      as num?)?.toDouble()  ??
                       (json['longitude'] as num?)?.toDouble() ?? 0.0,
        walkingTime:   json['walkingTime']    as String?,
        arrivalTime:   json['arrivalTime']    as String?,
        departureTime: json['departureTime']  as String?,
        additionalInfo:json['additionalInfo'] as Map<String, dynamic>?,
      );
    }

    // ── Legacy v1 format: plain `name` and `line` strings ───────────────────
    return MetroStation(
      id:            json['id']        as String,
      cityId:        json['cityId']    as String? ?? 'hyd',
      names:         {'en': json['name'] as String? ?? ''},
      lineIds:       json['line'] != null ? [json['line'] as String] : [],
      distance:      (json['distance'] as num?)?.toDouble()  ?? 0.0,
      latitude:      (json['latitude'] as num?)?.toDouble()  ?? 0.0,
      longitude:     (json['longitude'] as num?)?.toDouble() ?? 0.0,
      walkingTime:   json['walkingTime']    as String?,
      arrivalTime:   json['arrivalTime']    as String?,
      departureTime: json['departureTime']  as String?,
      additionalInfo:json['additionalInfo'] as Map<String, dynamic>?,
    );
  }

  /// Returns a line color based on the city-specific line id.
  /// Pass [cityLineColors] from the active City's lines for accuracy;
  /// falls back to generic color-name heuristic for legacy data.
  int getLineColor({Map<String, int>? cityLineColors}) {
    if (cityLineColors != null && lineIds.isNotEmpty) {
      return cityLineColors[lineIds.first] ?? 0xFF757575;
    }
    // Legacy fallback
    final l = line.toLowerCase();
    if (l.contains('red'))    return 0xFFE53935;
    if (l.contains('blue'))   return 0xFF1E88E5;
    if (l.contains('green'))  return 0xFF43A047;
    if (l.contains('yellow')) return 0xFFFFC107;
    if (l.contains('purple')) return 0xFF7C3AED;
    if (l.contains('violet')) return 0xFF7C3AED;
    if (l.contains('pink'))   return 0xFFEC4899;
    if (l.contains('magenta'))return 0xFFA21CAF;
    return 0xFF757575;
  }

  String getAccessInfo() {
    if (walkingTime != null) {
      return '$walkingTime walk • ${distance.toStringAsFixed(1)} km';
    }
    return '${(distance * 12).round()} mins walk • ${distance.toStringAsFixed(1)} km';
  }

  bool isOnSameLineAs(MetroStation other) {
    return lineIds.any((l) => other.lineIds.contains(l));
  }

  String getGoogleMapsUrl() {
    return 'https://www.google.com/maps/search/?api=1&query=${Uri.encodeComponent(name)}'
        '&query=$latitude,$longitude';
  }

  @override
  String toString() =>
      'MetroStation(id: $id, city: $cityId, name: $name, lines: $lineIds, dist: ${distance.toStringAsFixed(1)} km)';
}

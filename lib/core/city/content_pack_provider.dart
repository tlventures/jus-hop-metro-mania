// lib/core/city/content_pack_provider.dart
//
// Providers that fetch per-city content packs and cache them in
// SharedPreferences for offline / tunnel resilience.

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/api_config.dart';
import '../../services/telemetry.dart';
import 'content_pack_models.dart';
import 'current_city_provider.dart';

class ContentPackService {
  static const _cachePrefix = 'city_content_v1_';
  static const _staleDuration = Duration(hours: 12);

  final http.Client _client;
  ContentPackService({http.Client? client}) : _client = client ?? http.Client();

  Uri _uri(String cityId, String type) =>
      Uri.parse('${ApiConfig.baseUrl}/api/v2/cities/$cityId/content/$type');

  /// Fetch raw content pack as JSON, with cache.
  Future<Map<String, dynamic>?> fetchRaw(String cityId, String type, {bool forceRefresh = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final cacheKey = '$_cachePrefix${cityId}_$type';
    final cacheJson  = prefs.getString(cacheKey);
    final cacheTimeMs = prefs.getInt('${cacheKey}_ts') ?? 0;
    final stale = DateTime.now().millisecondsSinceEpoch - cacheTimeMs > _staleDuration.inMilliseconds;

    if (!forceRefresh && cacheJson != null && !stale) {
      try {
        return Map<String, dynamic>.from(jsonDecode(cacheJson) as Map);
      } catch (e, st) {
        Telemetry.recordNonFatal(e, st, reason: 'content_pack_cache_parse');
        /* fall through */
      }
    }

    try {
      final res = await _client.get(_uri(cityId, type)).timeout(const Duration(seconds: 12));
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final data = Map<String, dynamic>.from(body['data'] as Map);
        await prefs.setString(cacheKey, jsonEncode(data));
        await prefs.setInt('${cacheKey}_ts', DateTime.now().millisecondsSinceEpoch);
        return data;
      }
      if (res.statusCode == 404) {
        // No content pack — return cached (possibly stale) data if any, else null.
        if (cacheJson != null) return Map<String, dynamic>.from(jsonDecode(cacheJson) as Map);
        return null;
      }
    } catch (e) {
      debugPrint('ContentPackService.fetchRaw error: $e');
      if (cacheJson != null) {
        try {
          return Map<String, dynamic>.from(jsonDecode(cacheJson) as Map);
        } catch (e2, st2) {
          Telemetry.recordNonFatal(e2, st2, reason: 'content_pack_stale_cache_parse');
        }
      }
    }
    return null;
  }
}

// ── Providers ────────────────────────────────────────────────────────────────

final contentPackServiceProvider = Provider<ContentPackService>((ref) => ContentPackService());

/// City trivia pack — falls back to an empty pack if not available.
final cityTriviaPackProvider = FutureProvider<TriviaPack>((ref) async {
  final city = ref.watch(activeCityProvider);
  if (city == null) {
    return const TriviaPack(cityId: '', defaultLocale: 'en', categories: []);
  }
  final svc = ref.read(contentPackServiceProvider);
  final raw = await svc.fetchRaw(city.id, 'trivia');
  if (raw == null) {
    return TriviaPack(cityId: city.id, defaultLocale: city.defaultLocale, categories: const []);
  }
  return TriviaPack.fromJson(raw);
});

/// City landmarks pack for City Explorer game.
final cityLandmarksProvider = FutureProvider<LandmarksPack>((ref) async {
  final city = ref.watch(activeCityProvider);
  if (city == null) {
    return const LandmarksPack(cityId: '', landmarks: []);
  }
  final svc = ref.read(contentPackServiceProvider);
  final raw = await svc.fetchRaw(city.id, 'landmarks');
  if (raw == null) return LandmarksPack(cityId: city.id, landmarks: const []);
  return LandmarksPack.fromJson(raw);
});

/// City stamps catalogue.
final cityStampCatalogueProvider = FutureProvider<StampsPack>((ref) async {
  final city = ref.watch(activeCityProvider);
  if (city == null) return const StampsPack(cityId: '', collections: []);
  final svc = ref.read(contentPackServiceProvider);
  final raw = await svc.fetchRaw(city.id, 'stamps');
  if (raw == null) return StampsPack(cityId: city.id, collections: const []);
  return StampsPack.fromJson(raw);
});

/// City sudoku icon pack — used to swap the 1-9 digits with city emojis.
final citySudokuIconsProvider = FutureProvider<SudokuIconPack?>((ref) async {
  final city = ref.watch(activeCityProvider);
  if (city == null) return null;
  final svc = ref.read(contentPackServiceProvider);
  final raw = await svc.fetchRaw(city.id, 'sudoku_icons');
  if (raw == null) return null;
  final pack = SudokuIconPack.fromJson(raw);
  return pack.isValid ? pack : null;
});

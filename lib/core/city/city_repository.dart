// lib/core/city/city_repository.dart
//
// Fetches and caches city data from the v2 backend.
// Cache uses SharedPreferences (JSON). City bundles survive offline / tunnel.

import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/api_config.dart';
import '../../models/metro_station.dart';
import '../../services/telemetry.dart';
import 'city_model.dart';

class CityRepository {
  static const _cachePrefix = 'city_bundle_v1_';
  static const _citiesListKey = 'cities_list_v1';
  static const _staleDuration = Duration(hours: 6);

  /// In-app fallback so onboarding still works when the backend has no
  /// `/api/v2/cities` route deployed. Replace/extend once that service is
  /// live. Kept minimal on purpose — one row, real operator name, real ONDC
  /// city code (std:040 = Hyderabad).
  static final List<CitySummary> _builtInCities = [
    const CitySummary(
      id: 'hyderabad',
      name: {'en': 'Hyderabad'},
      status: CityStatus.live,
      operatorShortName: 'HMRL',
    ),
  ];

  /// Minimal Hyderabad bundle so `fetchCity('hyderabad')` returns something
  /// usable when `/api/v2/cities/{id}/bundle` is not deployed. Stations are
  /// real HMRL Red Line endpoints; add more here as needed for QA.
  static Map<String, dynamic> _builtInBundle(String cityId) {
    if (cityId != 'hyderabad') return {};
    return {
      'id': 'hyderabad',
      'name': {'en': 'Hyderabad'},
      'operator': {'id': 'hmrl', 'name': 'Hyderabad Metro Rail Limited', 'shortName': 'HMRL'},
      'country': 'IN',
      'timezone': 'Asia/Kolkata',
      'primaryLocales': ['en', 'te', 'hi'],
      'defaultLocale': 'en',
      'status': 'live',
      'lines': [],
      'stations': [
        {
          'id': 'hyd_red_miyapur',
          'cityId': 'hyd',
          'names': {'en': 'Miyapur'},
          'code': 'MYP',
          'lineIds': ['red'],
          'latitude': 17.4959,
          'longitude': 78.3612,
        },
        {
          'id': 'hyd_red_kphb',
          'cityId': 'hyd',
          'names': {'en': 'KPHB Colony'},
          'code': 'KPH',
          'lineIds': ['red'],
          'latitude': 17.4849,
          'longitude': 78.3915,
        },
        {
          'id': 'hyd_red_ameerpet',
          'cityId': 'hyd',
          'names': {'en': 'Ameerpet'},
          'code': 'AMP',
          'lineIds': ['red', 'blue'],
          'latitude': 17.4374,
          'longitude': 78.4482,
        },
        {
          'id': 'hyd_red_mgbs',
          'cityId': 'hyd',
          'names': {'en': 'MG Bus Station'},
          'code': 'MGB',
          'lineIds': ['red', 'green'],
          'latitude': 17.3782,
          'longitude': 78.4867,
        },
        {
          'id': 'hyd_red_dilsukhnagar',
          'cityId': 'hyd',
          'names': {'en': 'Dilsukhnagar'},
          'code': 'DSN',
          'lineIds': ['red'],
          'latitude': 17.3687,
          'longitude': 78.5247,
        },
        {
          'id': 'hyd_red_lbnagar',
          'cityId': 'hyd',
          'names': {'en': 'LB Nagar'},
          'code': 'LBN',
          'lineIds': ['red'],
          'latitude': 17.3479,
          'longitude': 78.5525,
        },
      ],
    };
  }

  final http.Client _client;
  CityRepository({http.Client? client}) : _client = client ?? http.Client();

  Uri _v2(String path) => Uri.parse('${ApiConfig.baseUrl}/api/v2$path');

  // ── City list ─────────────────────────────────────────────────────────────

  /// Fetch summary list of all cities. Returns cached if fresh.
  Future<List<CitySummary>> fetchCitySummaries({bool forceRefresh = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final cacheJson  = prefs.getString(_citiesListKey);
    final cacheTimeMs = prefs.getInt('${_citiesListKey}_ts') ?? 0;
    final stale = DateTime.now().millisecondsSinceEpoch - cacheTimeMs > _staleDuration.inMilliseconds;

    if (!forceRefresh && cacheJson != null && !stale) {
      try {
        final list = jsonDecode(cacheJson) as List;
        return list.map((j) => CitySummary.fromJson(Map<String, dynamic>.from(j as Map))).toList();
      } catch (e, st) {
        Telemetry.recordNonFatal(e, st, reason: 'city_summaries_cache_parse');
        /* fall through to network */
      }
    }

    try {
      final res = await _client.get(_v2('/cities')).timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final cities = body['cities'] as List;
        await prefs.setString(_citiesListKey, jsonEncode(cities));
        await prefs.setInt('${_citiesListKey}_ts', DateTime.now().millisecondsSinceEpoch);
        return cities.map((j) => CitySummary.fromJson(Map<String, dynamic>.from(j as Map))).toList();
      }
    } catch (e) {
      debugPrint('CityRepository.fetchCitySummaries error: $e');
    }

    // Return stale cache if network failed
    if (cacheJson != null) {
      try {
        final list = jsonDecode(cacheJson) as List;
        return list.map((j) => CitySummary.fromJson(Map<String, dynamic>.from(j as Map))).toList();
      } catch (e, st) {
        Telemetry.recordNonFatal(e, st, reason: 'city_summaries_stale_cache_parse');
      }
    }
    // Backend has no /api/v2/cities yet — ship a static Hyderabad row so
    // onboarding never dead-ends. Remove once the v2 service is deployed.
    return List<CitySummary>.from(_builtInCities);
  }

  // ── City resolve ──────────────────────────────────────────────────────────

  /// Ask the backend which city a lat/lng belongs to.
  /// Returns { status, cityId, distanceKm? }.
  Future<Map<String, dynamic>> resolveCity(double lat, double lng) async {
    try {
      final res = await _client
          .get(_v2('/cities/resolve?lat=$lat&lng=$lng'))
          .timeout(const Duration(seconds: 8));
      if (res.statusCode == 200) {
        return Map<String, dynamic>.from(jsonDecode(res.body) as Map);
      }
    } catch (e) {
      debugPrint('CityRepository.resolveCity error: $e');
    }
    return {'status': 'error'};
  }

  // ── City bundle ───────────────────────────────────────────────────────────

  /// Load a full city bundle (metadata + stations). Returns cached if fresh.
  Future<City?> fetchCity(String cityId, {bool forceRefresh = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final cacheKey = '$_cachePrefix$cityId';
    final cacheJson  = prefs.getString(cacheKey);
    final cacheTimeMs = prefs.getInt('${cacheKey}_ts') ?? 0;
    final stale = DateTime.now().millisecondsSinceEpoch - cacheTimeMs > _staleDuration.inMilliseconds;

    if (!forceRefresh && cacheJson != null && !stale) {
      try {
        return City.fromJson(Map<String, dynamic>.from(jsonDecode(cacheJson) as Map));
      } catch (e, st) {
        Telemetry.recordNonFatal(e, st, reason: 'city_bundle_cache_parse');
      }
    }

    try {
      // Use the bundle endpoint so we get city + stations in one shot
      final res = await _client
          .get(_v2('/cities/$cityId/bundle'))
          .timeout(const Duration(seconds: 15));
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final bundleJson = Map<String, dynamic>.from(body['bundle'] as Map);
        await prefs.setString(cacheKey, jsonEncode(bundleJson));
        await prefs.setInt('${cacheKey}_ts', DateTime.now().millisecondsSinceEpoch);
        return City.fromJson(bundleJson);
      }
    } catch (e) {
      debugPrint('CityRepository.fetchCity error: $e');
    }

    // Stale cache as last resort
    if (cacheJson != null) {
      try {
        return City.fromJson(Map<String, dynamic>.from(jsonDecode(cacheJson) as Map));
      } catch (e, st) {
        Telemetry.recordNonFatal(e, st, reason: 'city_bundle_stale_cache_parse');
      }
    }
    // Built-in Hyderabad bundle when v2 backend isn't deployed.
    final builtin = _builtInBundle(cityId);
    if (builtin.isNotEmpty) return City.fromJson(builtin);
    return null;
  }

  // ── Stations ──────────────────────────────────────────────────────────────

  /// Fetch stations for a city. Bundled into city bundle; this is a fallback.
  Future<List<MetroStation>> fetchStations(String cityId) async {
    try {
      final res = await _client
          .get(_v2('/cities/$cityId/stations'))
          .timeout(const Duration(seconds: 10));
      if (res.statusCode == 200) {
        final body = jsonDecode(res.body) as Map<String, dynamic>;
        final list = body['stations'] as List? ?? [];
        return list.map((s) => MetroStation.fromJson(Map<String, dynamic>.from(s as Map))).toList();
      }
    } catch (e) {
      debugPrint('CityRepository.fetchStations error: $e');
    }
    // Fall back to the built-in bundle's stations so booking still works.
    final builtin = _builtInBundle(cityId);
    final list = builtin['stations'] as List? ?? [];
    return list.map((s) => MetroStation.fromJson(Map<String, dynamic>.from(s as Map))).toList();
  }

  // ── Active city preference ────────────────────────────────────────────────

  Future<String?> getSavedCityId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('active_city_id');
  }

  Future<void> saveCityId(String cityId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('active_city_id', cityId);
  }

  // ── Waitlist ──────────────────────────────────────────────────────────────

  Future<bool> joinWaitlist({required String email, String? cityId, double? lat, double? lng}) async {
    try {
      final res = await _client.post(
        _v2('/waitlist'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email, 'cityId': cityId, 'lat': lat, 'lng': lng}),
      ).timeout(const Duration(seconds: 10));
      return res.statusCode == 200;
    } catch (e) {
      debugPrint('CityRepository.joinWaitlist error: $e');
      return false;
    }
  }
}

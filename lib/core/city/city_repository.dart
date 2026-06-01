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
import 'city_model.dart';

class CityRepository {
  static const _cachePrefix = 'city_bundle_v1_';
  static const _citiesListKey = 'cities_list_v1';
  static const _staleDuration = Duration(hours: 6);

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
      } catch (_) { /* fall through to network */ }
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
      } catch (_) {}
    }
    return [];
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
      } catch (_) {}
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
      } catch (_) {}
    }
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
    return [];
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

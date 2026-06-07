// lib/services/location_service.dart
//
// Multi-city aware location service.
// All station lookups now receive the city's station list as a parameter
// rather than pulling from the old Constants.metroStations hardcoded list.

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../models/metro_station.dart';
import '../utils/constants.dart';
import 'telemetry.dart';

class LocationService {
  /// Whether the Google Maps Distance Matrix integration is both enabled AND
  /// has a key. When enabled without a key we log once (so the misconfiguration
  /// is visible instead of silently degrading) and fall back to local distance.
  static bool _warnedMissingMapsKey = false;
  static bool get _mapsApiUsable {
    if (!Constants.useRealGoogleMapsApi) return false;
    if (Constants.googleMapsApiKey.isEmpty) {
      if (!_warnedMissingMapsKey) {
        _warnedMissingMapsKey = true;
        Telemetry.recordNonFatal(
          StateError('METROSAFAR_MAPS_API_KEY missing'),
          StackTrace.current,
          reason: 'maps_api_enabled_without_key_falling_back_to_local',
        );
      }
      return false;
    }
    return true;
  }
  // ── Location permission / position ────────────────────────────────────────

  Future<Position> getCurrentLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) throw Exception('Location services are disabled.');

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        throw Exception('Location permissions are denied.');
      }
    }
    if (permission == LocationPermission.deniedForever) {
      throw Exception('Location permissions are permanently denied.');
    }

    return await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    );
  }

  // ── Nearest station — city-aware ──────────────────────────────────────────

  /// Returns the nearest station from [cityStations] to [userPos].
  /// Pass `ref.read(cityStationsProvider)` as cityStations.
  MetroStation? getNearestStation(
    Position userPos,
    List<MetroStation> cityStations,
  ) {
    if (cityStations.isEmpty) return null;

    MetroStation nearest = cityStations.first;
    double minDist = Geolocator.distanceBetween(
      userPos.latitude,
      userPos.longitude,
      nearest.latitude,
      nearest.longitude,
    );

    for (final s in cityStations.skip(1)) {
      final d = Geolocator.distanceBetween(
        userPos.latitude,
        userPos.longitude,
        s.latitude,
        s.longitude,
      );
      if (d < minDist) {
        minDist = d;
        nearest = s;
      }
    }
    return nearest;
  }

  /// Returns the [Constants.nearbyStationsLimit] closest stations from [cityStations].
  Future<List<MetroStation>> getNearbyStations(
    Position position,
    List<MetroStation> cityStations, {
    bool useGoogleMaps = false,
  }) async {
    if (cityStations.isEmpty) return [];

    if (useGoogleMaps && _mapsApiUsable) {
      return _getNearbyStationsViaGoogleMapsAPI(position, cityStations);
    }
    return _getNearbyStationsLocally(position, cityStations);
  }

  List<MetroStation> _getNearbyStationsLocally(
    Position position,
    List<MetroStation> allStations,
  ) {
    final withDist =
        allStations.map((s) {
          final distM = Geolocator.distanceBetween(
            position.latitude,
            position.longitude,
            s.latitude,
            s.longitude,
          );
          return s.copyWith(
            distance: double.parse((distM / 1000).toStringAsFixed(1)),
          );
        }).toList();
    withDist.sort((a, b) => a.distance.compareTo(b.distance));
    return withDist.take(Constants.nearbyStationsLimit).toList();
  }

  // ── Google Maps integration ───────────────────────────────────────────────

  Future<List<MetroStation>> _getNearbyStationsViaGoogleMapsAPI(
    Position position,
    List<MetroStation> allStations,
  ) async {
    try {
      const chunkSize = 20;
      final chunks = <List<MetroStation>>[];
      for (int i = 0; i < allStations.length; i += chunkSize) {
        chunks.add(
          allStations.sublist(i, (i + chunkSize).clamp(0, allStations.length)),
        );
      }

      final results = await Future.wait(
        chunks.map((c) => _fetchChunkDistances(c, position)),
      );

      final flat = results.expand((l) => l).toList();
      flat.sort((a, b) => a.distance.compareTo(b.distance));
      return flat.take(Constants.nearbyStationsLimit).toList();
    } catch (e) {
      debugPrint('getNearbyStationsViaGoogleMapsAPI error: $e');
      return _getNearbyStationsLocally(position, allStations);
    }
  }

  Future<List<MetroStation>> _fetchChunkDistances(
    List<MetroStation> chunk,
    Position position,
  ) async {
    try {
      final origin = '${position.latitude},${position.longitude}';
      final dests = chunk.map((s) => '${s.latitude},${s.longitude}').join('|');
      final key = Constants.googleMapsApiKey;
      final url =
          'https://maps.googleapis.com/maps/api/distancematrix/json'
          '?origins=$origin&destinations=$dests&mode=walking&units=metric&key=$key';

      final res = await http.get(Uri.parse(url));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        if (data['status'] == 'OK') {
          final elements = (data['rows'] as List).first['elements'] as List;
          return [
            for (int i = 0; i < elements.length && i < chunk.length; i++)
              if ((elements[i] as Map)['status'] == 'OK')
                chunk[i].copyWith(
                  distance:
                      ((elements[i]['distance']['value'] as num) / 1000)
                          .toDouble(),
                  walkingTime: elements[i]['duration']['text'] as String?,
                )
              else
                _localDistance(chunk[i], position),
          ];
        }
      }
    } catch (e) {
      debugPrint('_fetchChunkDistances error: $e');
    }
    return chunk.map((s) => _localDistance(s, position)).toList();
  }

  MetroStation _localDistance(MetroStation s, Position pos) {
    final distKm =
        Geolocator.distanceBetween(
          pos.latitude,
          pos.longitude,
          s.latitude,
          s.longitude,
        ) /
        1000;
    return s.copyWith(distance: double.parse(distKm.toStringAsFixed(1)));
  }

  // ── Fare calculation (city-aware) ─────────────────────────────────────────

  /// Calculate fare between two stations within [cityStations].
  /// [maxFare] is taken from the city's fareGrammar (defaults to Constants.maxFare).
  Future<int> calculateFare(
    String fromId,
    String toId,
    List<MetroStation> cityStations, {
    int maxFare = 60,
  }) async {
    try {
      if (_mapsApiUsable) {
        return await _calculateFareViaAPI(
          fromId,
          toId,
          cityStations,
          maxFare: maxFare,
        );
      }
      return _calculateFareLocally(
        fromId,
        toId,
        cityStations,
        maxFare: maxFare,
      );
    } catch (e) {
      debugPrint('calculateFare error: $e');
      return Constants.baseAdultFare;
    }
  }

  int _calculateFareLocally(
    String fromId,
    String toId,
    List<MetroStation> cityStations, {
    int maxFare = 60,
  }) {
    final stationMap = {for (final s in cityStations) s.id: s};
    final from = stationMap[fromId];
    final to = stationMap[toId];
    if (from == null || to == null) throw Exception('Station not found');

    final distKm =
        Geolocator.distanceBetween(
          from.latitude,
          from.longitude,
          to.latitude,
          to.longitude,
        ) /
        1000;
    int fare = 10;
    if (distKm > 2) fare += ((distKm - 2) / 2).ceil() * 5;
    return fare.clamp(0, maxFare);
  }

  Future<int> _calculateFareViaAPI(
    String fromId,
    String toId,
    List<MetroStation> cityStations, {
    int maxFare = 60,
  }) async {
    try {
      final stationMap = {for (final s in cityStations) s.id: s};
      final from = stationMap[fromId]!;
      final to = stationMap[toId]!;

      final url =
          'https://maps.googleapis.com/maps/api/distancematrix/json'
          '?origins=${from.latitude},${from.longitude}'
          '&destinations=${to.latitude},${to.longitude}'
          '&mode=transit&units=metric&key=${Constants.googleMapsApiKey}';

      final res = await http.get(Uri.parse(url));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        if (data['status'] == 'OK') {
          final el = (data['rows'] as List).first['elements'] as List;
          if (el.isNotEmpty && el.first['status'] == 'OK') {
            final distKm = (el.first['distance']['value'] as num) / 1000.0;
            int fare = 10;
            if (distKm > 2) fare += ((distKm - 2) / 2).ceil() * 5;
            return fare.clamp(0, maxFare);
          }
        }
      }
    } catch (e) {
      debugPrint('_calculateFareViaAPI error: $e');
    }
    return _calculateFareLocally(fromId, toId, cityStations, maxFare: maxFare);
  }

  // ── Route calculation (city-aware) ────────────────────────────────────────

  Future<List<MetroStation>> getRouteBetweenStations(
    String fromId,
    String toId,
    List<MetroStation> cityStations,
  ) async {
    try {
      if (_mapsApiUsable) {
        return await _getRouteViaAPI(fromId, toId, cityStations);
      }
      return _getRouteLocally(fromId, toId, cityStations);
    } catch (e) {
      debugPrint('getRouteBetweenStations error: $e');
      throw Exception('Failed to get route: $e');
    }
  }

  List<MetroStation> _getRouteLocally(
    String fromId,
    String toId,
    List<MetroStation> cityStations,
  ) {
    final stationMap = {for (final s in cityStations) s.id: s};
    final from = stationMap[fromId];
    final to = stationMap[toId];
    if (from == null || to == null) throw Exception('Station not found');

    // Same line — direct route
    final commonLines =
        from.lineIds.where((l) => to.lineIds.contains(l)).toList();
    if (commonLines.isNotEmpty) {
      final lineId = commonLines.first;
      final lineStations =
          cityStations.where((s) => s.lineIds.contains(lineId)).toList();
      final fromIdx = lineStations.indexWhere((s) => s.id == fromId);
      final toIdx = lineStations.indexWhere((s) => s.id == toId);
      if (fromIdx >= 0 && toIdx >= 0) {
        final slice =
            fromIdx <= toIdx
                ? lineStations.sublist(fromIdx, toIdx + 1)
                : lineStations.sublist(toIdx, fromIdx + 1).reversed.toList();
        return slice;
      }
    }

    // Multi-line: find an interchange station
    final interchanges =
        cityStations.where((s) => s.lineIds.length > 1).toList();
    for (final xfer in interchanges) {
      final connectsFrom = xfer.lineIds.any((l) => from.lineIds.contains(l));
      final connectsTo = xfer.lineIds.any((l) => to.lineIds.contains(l));
      if (connectsFrom && connectsTo) {
        final seg1 = _getRouteLocally(fromId, xfer.id, cityStations);
        final seg2 = _getRouteLocally(xfer.id, toId, cityStations);
        return [...seg1, ...seg2.sublist(1)];
      }
    }

    return [from, to]; // fallback
  }

  Future<List<MetroStation>> _getRouteViaAPI(
    String fromId,
    String toId,
    List<MetroStation> cityStations,
  ) async {
    // Delegate to local for now; swap in Directions API if needed
    return _getRouteLocally(fromId, toId, cityStations);
  }
}

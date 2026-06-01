// lib/core/city/current_city_provider.dart
//
// The single source of truth for which city the current user is in.
// All screens, services, and providers must consume this — never access
// Constants.metroStations or hardcoded city data directly.
//
// State machine:
//   resolving  → detecting city from location
//   confirmed  → city resolved and loaded
//   unsupported → location detected but no city available (waitlist)
//   manual     → user picked a city manually
//   error      → something failed badly

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import '../../models/metro_station.dart';
import 'city_model.dart';
import 'city_repository.dart';

enum CityResolutionStatus {
  idle,
  resolving,
  confirmed,
  unsupported,
  manual,
  error,
}

class CityState {
  final CityResolutionStatus status;
  final City? city;
  final List<MetroStation> stations;
  final String? nearestCityId;    // set when status==unsupported
  final String? errorMessage;

  const CityState({
    required this.status,
    this.city,
    this.stations = const [],
    this.nearestCityId,
    this.errorMessage,
  });

  bool get isResolved => status == CityResolutionStatus.confirmed || status == CityResolutionStatus.manual;
  bool get hasCity => city != null;

  CityState copyWith({
    CityResolutionStatus? status,
    City? city,
    List<MetroStation>? stations,
    String? nearestCityId,
    String? errorMessage,
  }) => CityState(
        status:        status        ?? this.status,
        city:          city          ?? this.city,
        stations:      stations      ?? this.stations,
        nearestCityId: nearestCityId ?? this.nearestCityId,
        errorMessage:  errorMessage  ?? this.errorMessage,
      );
}

class CurrentCityNotifier extends StateNotifier<CityState> {
  final CityRepository _repo;

  CurrentCityNotifier(this._repo) : super(const CityState(status: CityResolutionStatus.idle));

  /// Called on app start — tries saved preference first, then geo-resolve.
  Future<void> initialize() async {
    state = const CityState(status: CityResolutionStatus.resolving);

    // 1. Try previously saved city
    final savedId = await _repo.getSavedCityId();
    if (savedId != null) {
      final city = await _repo.fetchCity(savedId);
      if (city != null) {
        final stations = _extractStations(city);
        state = CityState(status: CityResolutionStatus.confirmed, city: city, stations: stations);
        return;
      }
    }

    // 2. Try geo-resolve
    await _resolveFromLocation();
  }

  Future<void> _resolveFromLocation() async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        // No location permission — fall back to Hyderabad as default
        await _loadCity('hyd');
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      ).timeout(const Duration(seconds: 8));

      final result = await _repo.resolveCity(position.latitude, position.longitude);
      final status = result['status'] as String? ?? 'error';

      if (status == 'found' || status == 'nearby') {
        final cityId = result['cityId'] as String;
        await _loadCity(cityId);
      } else {
        // Unsupported city
        state = CityState(
          status: CityResolutionStatus.unsupported,
          nearestCityId: result['nearestCityId'] as String?,
        );
      }
    } catch (e) {
      debugPrint('CurrentCityNotifier._resolveFromLocation error: $e');
      // Network error or location timeout — fall back to Hyderabad
      await _loadCity('hyd');
    }
  }

  Future<void> _loadCity(String cityId) async {
    try {
      final city = await _repo.fetchCity(cityId);
      if (city == null) {
        state = CityState(status: CityResolutionStatus.error, errorMessage: 'Could not load city data for $cityId');
        return;
      }
      final stations = _extractStations(city);
      await _repo.saveCityId(cityId);
      state = CityState(status: CityResolutionStatus.confirmed, city: city, stations: stations);
    } catch (e) {
      state = CityState(status: CityResolutionStatus.error, errorMessage: e.toString());
    }
  }

  /// User explicitly picked a city (from onboarding or profile).
  Future<void> switchCity(String cityId) async {
    state = state.copyWith(status: CityResolutionStatus.resolving);
    final city = await _repo.fetchCity(cityId, forceRefresh: true);
    if (city == null) {
      state = state.copyWith(status: CityResolutionStatus.error, errorMessage: 'Could not load $cityId');
      return;
    }
    final stations = _extractStations(city);
    await _repo.saveCityId(cityId);
    state = CityState(status: CityResolutionStatus.manual, city: city, stations: stations);
  }

  /// Confirm the auto-detected city (called from onboarding confirm sheet).
  Future<void> confirmCity(String cityId) async {
    await _repo.saveCityId(cityId);
    if (state.city?.id == cityId) {
      state = state.copyWith(status: CityResolutionStatus.confirmed);
    } else {
      await _loadCity(cityId);
    }
  }

  List<MetroStation> _extractStations(City city) {
    return city.stations;
  }
}

// ── Providers ────────────────────────────────────────────────────────────────

final cityRepositoryProvider = Provider<CityRepository>((ref) => CityRepository());

final currentCityProvider = StateNotifierProvider<CurrentCityNotifier, CityState>((ref) {
  return CurrentCityNotifier(ref.read(cityRepositoryProvider));
});

/// Convenience: just the resolved City (or null while loading).
final activeCityProvider = Provider<City?>((ref) => ref.watch(currentCityProvider).city);

/// Convenience: stations for the active city.
final cityStationsProvider = Provider<List<MetroStation>>((ref) {
  return ref.watch(currentCityProvider).stations;
});

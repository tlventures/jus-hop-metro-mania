import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metrosafar/core/commute/commute_provider.dart';
import 'package:metrosafar/core/commute/commute_session.dart';
import 'package:metrosafar/core/commute/ride_verification.dart';
import 'package:metrosafar/models/metro_station.dart';
import 'package:metrosafar/services/backend_service.dart';
import 'package:metrosafar/services/location_service.dart';

class TripModeState {
  final bool isLoading;
  final List<MetroStation> stations;
  final Map<String, dynamic>? activeTrip;
  final String? selectedStartStationId;
  final String? selectedEndStationId;
  final String? statusMessage;
  final int outboxCount;
  final Duration elapsed;
  final int pointsEarnedThisRide;

  const TripModeState({
    this.isLoading = true,
    this.stations = const [],
    this.activeTrip,
    this.selectedStartStationId,
    this.selectedEndStationId,
    this.statusMessage,
    this.outboxCount = 0,
    this.elapsed = Duration.zero,
    this.pointsEarnedThisRide = 0,
  });

  bool get hasActiveTrip => activeTrip != null;

  // Remaining minutes based on expected duration from backend
  int get remainingMinutes {
    if (activeTrip == null) return 0;
    final expectedSecs =
        (activeTrip!['expectedDurationSeconds'] as num?)?.toInt() ?? 1200;
    final remaining = expectedSecs - elapsed.inSeconds;
    return (remaining / 60).ceil().clamp(0, 60);
  }

  TripModeState copyWith({
    bool? isLoading,
    List<MetroStation>? stations,
    Map<String, dynamic>? activeTrip,
    bool clearActiveTrip = false,
    String? selectedStartStationId,
    String? selectedEndStationId,
    String? statusMessage,
    int? outboxCount,
    Duration? elapsed,
    int? pointsEarnedThisRide,
  }) {
    return TripModeState(
      isLoading: isLoading ?? this.isLoading,
      stations: stations ?? this.stations,
      activeTrip: clearActiveTrip ? null : activeTrip ?? this.activeTrip,
      selectedStartStationId:
          selectedStartStationId ?? this.selectedStartStationId,
      selectedEndStationId: selectedEndStationId ?? this.selectedEndStationId,
      statusMessage: statusMessage,
      outboxCount: outboxCount ?? this.outboxCount,
      elapsed: elapsed ?? this.elapsed,
      pointsEarnedThisRide: pointsEarnedThisRide ?? this.pointsEarnedThisRide,
    );
  }
}

class TripModeNotifier extends StateNotifier<TripModeState> {
  final BackendService _backendService;
  final LocationService _locationService;
  final Ref _ref;
  Timer? _elapsedTimer;

  TripModeNotifier(
    this._backendService,
    this._ref, {
    LocationService? locationService,
  }) : _locationService = locationService ?? LocationService(),
       super(const TripModeState()) {
    _ref.listen<CommuteSessionState>(commuteProvider, (_, next) {
      _syncFromCommute(next);
    });
  }

  @override
  void dispose() {
    _elapsedTimer?.cancel();
    super.dispose();
  }

  Future<void> load() async {
    state = state.copyWith(isLoading: true);
    try {
      final stations = await _backendService.getStations();
      await _ref
          .read(commuteProvider.notifier)
          .restoreActiveSession(stations: stations);
      final outboxCount = await _backendService.outboxCount();
      final commute = _ref.read(commuteProvider);
      final trip = _tripFromCommute(commute, stations);

      // Auto-select the nearest station as "Board at" when the user hasn't
      // chosen one and there's no active trip. Best-effort: silently keeps the
      // current selection if location is unavailable/denied.
      var startId = state.selectedStartStationId;
      if (trip == null && startId == null && stations.isNotEmpty) {
        startId = await _nearestStationId(stations);
      }

      state = state.copyWith(
        isLoading: false,
        stations: stations,
        activeTrip: trip,
        clearActiveTrip: trip == null,
        selectedStartStationId: startId,
        selectedEndStationId: state.selectedEndStationId,
        outboxCount: outboxCount,
      );

      if (trip != null) _startTimer();
    } catch (error) {
      debugPrint('TripModeNotifier.load error: $error');
      state = state.copyWith(
        isLoading: false,
        statusMessage:
            'Trip Mode is using cached data until backend is reachable.',
      );
    }
  }

  /// Best-effort nearest-station lookup; returns null if location is
  /// unavailable or permission is denied (caller leaves the picker unset).
  Future<String?> _nearestStationId(List<MetroStation> stations) async {
    try {
      final pos = await _locationService.getCurrentLocation();
      return _locationService.getNearestStation(pos, stations)?.id;
    } catch (e) {
      debugPrint('TripModeNotifier: nearest-station lookup skipped: $e');
      return null;
    }
  }

  void selectStart(String stationId) =>
      state = state.copyWith(selectedStartStationId: stationId);
  void selectEnd(String stationId) =>
      state = state.copyWith(selectedEndStationId: stationId);

  Future<void> startVerifiedRide(
    RideVerification verification, {
    String? cityId,
  }) async {
    final startStationId =
        state.selectedStartStationId ??
        (state.stations.isNotEmpty ? state.stations.first.id : null);
    if (startStationId == null) return;
    state = state.copyWith(isLoading: true);
    try {
      final started = await _ref
          .read(commuteProvider.notifier)
          .startManual(cityId: cityId, ticketVerification: verification);
      if (!started) {
        state = state.copyWith(
          isLoading: false,
          statusMessage:
              'Ride Mode needs an official station QR code before points can start.',
        );
        return;
      }
      final trip = _tripFromCommute(_ref.read(commuteProvider), state.stations);
      final outboxCount = await _backendService.outboxCount();
      state = state.copyWith(
        isLoading: false,
        activeTrip: trip,
        elapsed: Duration.zero,
        pointsEarnedThisRide: 0,
        statusMessage: 'Ride Mode active. Eligible activities now earn points.',
        outboxCount: outboxCount,
      );
      if (trip != null) _startTimer();
    } catch (error) {
      debugPrint('TripModeNotifier.startVerifiedRide error: $error');
      state = state.copyWith(
        isLoading: false,
        statusMessage: 'Could not start trip.',
      );
    }
  }

  Future<void> endTrip() async {
    final trip = state.activeTrip;
    final endStationId =
        state.selectedEndStationId ??
        (state.stations.isNotEmpty ? state.stations.last.id : null);
    if (trip == null || endStationId == null) return;
    _stopTimers();
    state = state.copyWith(isLoading: true);
    try {
      final ended = await _ref
          .read(commuteProvider.notifier)
          .end(endStationId: endStationId);
      if (!ended) {
        _startTimer();
        state = state.copyWith(
          isLoading: false,
          statusMessage: 'Reconnect and try again to end Ride Mode.',
        );
        return;
      }
      final outboxCount = await _backendService.outboxCount();

      state = state.copyWith(
        isLoading: false,
        clearActiveTrip: true,
        elapsed: Duration.zero,
        statusMessage:
            'Ride complete. Points earned by verified activities are in your wallet.',
        outboxCount: outboxCount,
      );
    } catch (error) {
      debugPrint('TripModeNotifier.endTrip error: $error');
      state = state.copyWith(
        isLoading: false,
        statusMessage: 'Could not end trip.',
      );
    }
  }

  Future<void> flushOutbox() async {
    await _backendService.flushOutbox();
    state = state.copyWith(outboxCount: await _backendService.outboxCount());
    await load();
  }

  Map<String, dynamic>? _tripFromCommute(
    CommuteSessionState commute,
    List<MetroStation> stations,
  ) {
    if (!commute.isActive || commute.sessionId == null) return null;
    final station =
        commute.station ??
        stations
            .where((item) => item.id == state.selectedStartStationId)
            .firstOrNull;
    return {
      'id': commute.sessionId,
      'startStation': {
        'id': station?.id ?? state.selectedStartStationId,
        'name': station?.name ?? 'Verified station',
      },
      'startedAt': commute.startedAt?.toIso8601String(),
      'expectedDurationSeconds': 3 * 60 * 60,
      'rewardsEligible': commute.rewardsEligible,
    };
  }

  void _syncFromCommute(CommuteSessionState commute) {
    final trip = _tripFromCommute(commute, state.stations);
    state = state.copyWith(activeTrip: trip, clearActiveTrip: trip == null);
    if (trip == null) {
      _stopTimers();
    } else if (_elapsedTimer == null) {
      _startTimer();
    }
  }

  void _startTimer() {
    _elapsedTimer?.cancel();
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      state = state.copyWith(
        elapsed: state.elapsed + const Duration(seconds: 1),
      );
    });
  }

  void _stopTimers() {
    _elapsedTimer?.cancel();
    _elapsedTimer = null;
  }
}

final tripModeProvider = StateNotifierProvider<TripModeNotifier, TripModeState>(
  (ref) => TripModeNotifier(BackendService(), ref),
);

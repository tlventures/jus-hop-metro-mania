import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
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
    final expectedSecs = (activeTrip!['expectedDurationSeconds'] as num?)?.toInt() ?? 1200;
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
      selectedStartStationId: selectedStartStationId ?? this.selectedStartStationId,
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
  Timer? _elapsedTimer;
  Timer? _heartbeatTimer;

  TripModeNotifier(this._backendService, {LocationService? locationService})
      : _locationService = locationService ?? LocationService(),
        super(const TripModeState());

  @override
  void dispose() {
    _elapsedTimer?.cancel();
    _heartbeatTimer?.cancel();
    super.dispose();
  }

  Future<void> load() async {
    state = state.copyWith(isLoading: true);
    try {
      final stations = await _backendService.getStations();
      final active = await _backendService.getActiveTrip();
      final outboxCount = await _backendService.outboxCount();
      final trip = active['trip'] == null
          ? null
          : Map<String, dynamic>.from(active['trip'] as Map);

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

      if (trip != null) _startTimers(trip['id'] as String? ?? '');
    } catch (error) {
      debugPrint('TripModeNotifier.load error: $error');
      state = state.copyWith(
        isLoading: false,
        statusMessage: 'Trip Mode is using cached data until backend is reachable.',
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

  void selectStart(String stationId) => state = state.copyWith(selectedStartStationId: stationId);
  void selectEnd(String stationId)   => state = state.copyWith(selectedEndStationId: stationId);

  Future<void> startManualTrip() async {
    final startStationId = state.selectedStartStationId ??
        (state.stations.isNotEmpty ? state.stations.first.id : null);
    if (startStationId == null) return;
    state = state.copyWith(isLoading: true);
    try {
      final data = await _backendService.startTrip(startStationId: startStationId);
      final trip = data['trip'] == null
          ? null
          : Map<String, dynamic>.from(data['trip'] as Map);
      final outboxCount = await _backendService.outboxCount();
      state = state.copyWith(
        isLoading: false,
        activeTrip: trip,
        elapsed: Duration.zero,
        pointsEarnedThisRide: 0,
        statusMessage: data['queued'] == true
            ? 'Trip start saved offline — will sync automatically.'
            : null,
        outboxCount: outboxCount,
      );
      if (trip != null) _startTimers(trip['id'] as String? ?? '');

      // Award ride-started activity event and complete daily quest
      await _backendService.logActivityEvent(type: 'ride_started');
      try { await _backendService.completeQuest('ride_started'); } catch (_) {}
    } catch (error) {
      debugPrint('TripModeNotifier.startManualTrip error: $error');
      state = state.copyWith(isLoading: false, statusMessage: 'Could not start trip.');
    }
  }

  Future<void> endTrip() async {
    final trip = state.activeTrip;
    final endStationId = state.selectedEndStationId ??
        (state.stations.isNotEmpty ? state.stations.last.id : null);
    if (trip == null || endStationId == null) return;
    _stopTimers();
    state = state.copyWith(isLoading: true);
    try {
      final data = await _backendService.endTrip(
        tripId: trip['id'] as String,
        endStationId: endStationId,
      );
      // Award ride-completed event
      final result = await _backendService.logActivityEvent(type: 'ride_completed');
      final pts = (result['pointsAwarded'] as num?)?.toInt() ?? 0;
      final capReached = result['dailyCapReached'] == true ||
          result['reason'] == 'daily_cap_reached';
      final outboxCount = await _backendService.outboxCount();

      final String message;
      if (data['queued'] == true) {
        message = 'Trip end saved offline — will sync automatically.';
      } else if (capReached) {
        final cap = (result['dailyCap'] as num?)?.toInt() ?? 500;
        message =
            'Trip complete! You\'ve hit today\'s $cap-point limit — rides still '
            'count, and points reset tomorrow.';
      } else {
        message =
            'Trip complete! +${state.pointsEarnedThisRide + pts} pts earned this ride.';
      }

      state = state.copyWith(
        isLoading: false,
        clearActiveTrip: data['queued'] != true,
        elapsed: Duration.zero,
        pointsEarnedThisRide: state.pointsEarnedThisRide + pts,
        statusMessage: message,
        outboxCount: outboxCount,
      );
    } catch (error) {
      debugPrint('TripModeNotifier.endTrip error: $error');
      state = state.copyWith(isLoading: false, statusMessage: 'Could not end trip.');
    }
  }

  Future<void> flushOutbox() async {
    await _backendService.flushOutbox();
    state = state.copyWith(outboxCount: await _backendService.outboxCount());
    await load();
  }

  void _startTimers(String tripId) {
    _elapsedTimer?.cancel();
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      state = state.copyWith(elapsed: state.elapsed + const Duration(seconds: 1));
    });

    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (tripId.isNotEmpty) {
        _backendService.sendTripHeartbeat(tripId).catchError((e) {
          debugPrint('heartbeat error: $e');
          return <String, dynamic>{};
        });
      }
    });
  }

  void _stopTimers() {
    _elapsedTimer?.cancel();
    _heartbeatTimer?.cancel();
    _elapsedTimer = null;
    _heartbeatTimer = null;
  }
}

final tripModeProvider = StateNotifierProvider<TripModeNotifier, TripModeState>(
  (ref) => TripModeNotifier(BackendService()),
);

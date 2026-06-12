import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:metrosafar/models/metro_station.dart';
import 'package:metrosafar/services/backend_service.dart';
import 'package:metrosafar/core/ride/ride_session_provider.dart';

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
  final Ref _ref;
  Timer? _elapsedTimer;
  Timer? _heartbeatTimer;

  TripModeNotifier(this._backendService, this._ref) : super(const TripModeState());

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

      state = state.copyWith(
        isLoading: false,
        stations: stations,
        activeTrip: trip,
        clearActiveTrip: trip == null,
        selectedStartStationId: state.selectedStartStationId,
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

      // Complete the daily quest (quest system is separate from points)
      try { await _backendService.completeQuest('start_ride'); } catch (_) {}
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
      // Points come from endTrip directly — no separate ride_completed event needed
      final pts = (data['pointsAwarded'] as num?)?.toInt() ?? 0;
      final outboxCount = await _backendService.outboxCount();

      final String message;
      if (data['queued'] == true) {
        message = 'Trip end saved offline — will sync automatically.';
      } else {
        final reason = data['reason'] as String?;
        if (reason == 'daily_cap_reached') {
          message = 'Trip complete! You\'ve hit today\'s 500-point limit — points reset tomorrow.';
        } else if (pts == 0 && reason != null) {
          message = 'Trip complete! (No points: $reason)';
        } else {
          message = 'Trip complete! +${state.pointsEarnedThisRide + pts} pts earned this ride.';
        }
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
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 60), (_) async {
      if (tripId.isEmpty) return;
      // If the new ride system has an active ride, skip the legacy heartbeat
      // to avoid double GPS polling and duplicate Firestore writes.
      final newRide = _ref.read(rideSessionProvider);
      if (newRide.isActive) return;
      try {
        // Try to send real GPS; fall back to clientTimeMs-only on error.
        final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.low,
        ).timeout(const Duration(seconds: 6));
        final speedKmh = position.speed > 0 ? position.speed * 3.6 : 0.0;
        await _backendService.sendRideHeartbeat(
          tripId,
          lat: position.latitude,
          lng: position.longitude,
          speedKmh: speedKmh,
          accuracy: position.accuracy,
        );
      } catch (e) {
        debugPrint('heartbeat error (no GPS): $e');
        // Still send clientTimeMs-only heartbeat so the server knows we're alive.
        _backendService.sendTripHeartbeat(tripId).catchError((_) => <String, dynamic>{});
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
  (ref) => TripModeNotifier(BackendService(), ref),
);

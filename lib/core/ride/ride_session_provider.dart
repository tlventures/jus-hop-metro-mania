import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:safe_device/safe_device.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/backend_service.dart';
import '../city/current_city_provider.dart';

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

enum RidePhase { idle, verifying, awaitingNetwork, active, ending, summary }

class RideSessionState {
  final RidePhase phase;
  final String? rideId;
  final String? startStationId;
  final String? endStationId;
  final DateTime? startedAt;
  final DateTime? expiresAt;
  final int pointsEarned;
  final double co2SavedKg;
  final List<String> stamps;
  final String? statusMessage;
  final String? error;
  final Duration elapsed;

  const RideSessionState({
    this.phase = RidePhase.idle,
    this.rideId,
    this.startStationId,
    this.endStationId,
    this.startedAt,
    this.expiresAt,
    this.pointsEarned = 0,
    this.co2SavedKg = 0,
    this.stamps = const [],
    this.statusMessage,
    this.error,
    this.elapsed = Duration.zero,
  });

  bool get isActive => phase == RidePhase.active;
  bool get hasRide => rideId != null && (phase == RidePhase.active || phase == RidePhase.ending);

  Duration? get timeRemaining {
    if (expiresAt == null || phase != RidePhase.active) return null;
    final remaining = expiresAt!.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  RideSessionState copyWith({
    RidePhase? phase,
    String? rideId,
    bool clearRideId = false,
    String? startStationId,
    String? endStationId,
    DateTime? startedAt,
    DateTime? expiresAt,
    int? pointsEarned,
    double? co2SavedKg,
    List<String>? stamps,
    String? statusMessage,
    bool clearStatus = false,
    String? error,
    bool clearError = false,
    Duration? elapsed,
  }) {
    return RideSessionState(
      phase: phase ?? this.phase,
      rideId: clearRideId ? null : rideId ?? this.rideId,
      startStationId: startStationId ?? this.startStationId,
      endStationId: endStationId ?? this.endStationId,
      startedAt: startedAt ?? this.startedAt,
      expiresAt: expiresAt ?? this.expiresAt,
      pointsEarned: pointsEarned ?? this.pointsEarned,
      co2SavedKg: co2SavedKg ?? this.co2SavedKg,
      stamps: stamps ?? this.stamps,
      statusMessage: clearStatus ? null : statusMessage ?? this.statusMessage,
      error: clearError ? null : error ?? this.error,
      elapsed: elapsed ?? this.elapsed,
    );
  }
}

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

class RideSessionNotifier extends StateNotifier<RideSessionState> {
  final BackendService _backend;
  Timer? _heartbeatTimer;
  Timer? _elapsedTimer;

  // Pending QR scan — retained for reconnect retry
  String? _pendingQrToken;
  String? _pendingCityId;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;

  // SharedPreferences key for persisting ride summary
  static const String _summaryKey = 'ride_summary_pending';

  RideSessionNotifier(this._backend) : super(const RideSessionState());

  @override
  void dispose() {
    _stopTimers();
    _connectivitySub?.cancel();
    super.dispose();
  }

  /// Stop the legacy trip heartbeat timer to avoid duplicate GPS polling.
  /// Call this from TripModeNotifier when a new ride session becomes active.
  void stopLegacyHeartbeat() {
    // No-op here — the legacy provider owns its own timer.
    // This method exists so TripModeNotifier can be called the other way around.
  }

  /// Restore an in-progress ride from the backend (called on app launch).
  Future<void> restore() async {
    try {
      // Check for an unshown summary from a previous session first.
      final prefs = await SharedPreferences.getInstance();
      final uid = _backend.currentUid;
      if (uid != null) {
        final summaryJson = prefs.getString('${uid}_$_summaryKey');
        if (summaryJson != null) {
          try {
            final summary = jsonDecode(summaryJson) as Map<String, dynamic>;
            final savedAt = DateTime.tryParse(summary['savedAt'] as String? ?? '');
            if (savedAt != null && DateTime.now().difference(savedAt).inHours < 24) {
              state = state.copyWith(
                phase: RidePhase.summary,
                pointsEarned: (summary['pointsEarned'] as num?)?.toInt() ?? 0,
                co2SavedKg: (summary['co2SavedKg'] as num?)?.toDouble() ?? 0.0,
                stamps: (summary['stamps'] as List?)?.cast<String>() ?? [],
                statusMessage: summary['statusMessage'] as String?,
              );
              return; // show the summary; dismissSummary() will clear it
            }
          } catch (_) {}
          await prefs.remove('${uid}_$_summaryKey');
        }
      }

      final data = await _backend.getActiveRide();
      final ride = data['ride'] as Map<String, dynamic>?;
      if (ride != null) {
        _applyRideDoc(ride);
        _startTimers(ride['id'] as String);
      }
    } catch (e) {
      debugPrint('RideSessionNotifier.restore error: $e');
    }
  }

  /// Start a new ride using a scanned QR token.
  Future<void> startWithQr(String qrToken, {String? cityId}) async {
    state = state.copyWith(phase: RidePhase.verifying, clearError: true);
    try {
      final data = await _backend.startRide(qrToken: qrToken, cityId: cityId);
      if (data['queued'] == true) {
        // Network is down — retain the token and wait for reconnect.
        _pendingQrToken = qrToken;
        _pendingCityId = cityId;
        state = state.copyWith(
          phase: RidePhase.awaitingNetwork,
          statusMessage: 'No connection — will start ride automatically when signal returns.',
          clearError: true,
        );
        _watchForReconnect();
        return;
      }
      final ride = data['ride'] as Map<String, dynamic>?;
      if (ride == null) {
        state = state.copyWith(phase: RidePhase.idle, error: 'Could not start ride. Please try again.');
        return;
      }
      _clearPendingQr();
      _applyRideDoc(ride);
      _startTimers(ride['id'] as String);
    } catch (e) {
      state = state.copyWith(phase: RidePhase.idle, error: _friendlyError(e));
    }
  }

  /// Cancel a pending offline QR scan.
  void cancelPendingQr() {
    _clearPendingQr();
    state = state.copyWith(phase: RidePhase.idle, clearError: true, clearStatus: true);
  }

  /// End the active ride.
  Future<void> end({String? endStationId}) async {
    final rideId = state.rideId;
    if (rideId == null) return;
    state = state.copyWith(phase: RidePhase.ending);
    _stopTimers();
    try {
      final data = await _backend.endRide(rideId, endStationId: endStationId);
      final pts = (data['pointsAwarded'] as num?)?.toInt() ?? 0;
      final co2 = (data['co2SavedKg'] as num?)?.toDouble() ?? 0.0;
      final stamps = (data['stamps'] as List?)?.cast<String>() ?? [];
      final reason = data['reason'] as String?;
      final String message;
      if (pts > 0) {
        message = 'Ride complete! +$pts pts earned.';
      } else if (reason == 'cooldown') {
        message = 'Ride complete! Points paused — please slow down.';
      } else {
        message = reason == 'insufficient_evidence'
            ? 'Ride complete! Enable location for points next time.'
            : 'Ride complete!';
      }

      // Persist summary before showing it — survives a crash or backgrounding.
      await _saveSummary(pts, co2, stamps, message);

      state = state.copyWith(
        phase: RidePhase.summary,
        clearRideId: true,
        pointsEarned: pts,
        co2SavedKg: co2,
        stamps: stamps,
        statusMessage: message,
        elapsed: Duration.zero,
      );
    } catch (e) {
      state = state.copyWith(phase: RidePhase.active, error: _friendlyError(e));
      _startTimers(rideId);
    }
  }

  void dismissSummary() {
    _clearPersistedSummary();
    state = const RideSessionState();
  }

  // -------------------------------------------------------------------------

  void _applyRideDoc(Map<String, dynamic> ride) {
    final expiresAt = ride['expiresAt'] != null
        ? DateTime.tryParse(ride['expiresAt'] as String)
        : null;
    state = state.copyWith(
      phase: RidePhase.active,
      rideId: ride['id'] as String?,
      startStationId: ride['startStationId'] as String?,
      startedAt: DateTime.tryParse((ride['startedAt'] as String?) ?? ''),
      expiresAt: expiresAt,
      pointsEarned: 0,
      elapsed: Duration.zero,
      clearError: true,
      clearStatus: true,
    );
  }

  void _startTimers(String rideId) {
    _elapsedTimer?.cancel();
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      state = state.copyWith(elapsed: state.elapsed + const Duration(seconds: 1));
    });

    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 60), (_) async {
      if (state.rideId == null) return;
      try {
        bool isMock = false;
        try { isMock = await SafeDevice.isMockLocation; } catch (_) {}

        final position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.low,
        ).timeout(const Duration(seconds: 8));
        final speedKmh = position.speed > 0 ? position.speed * 3.6 : 0.0;
        await _backend.sendRideHeartbeat(
          rideId,
          lat: position.latitude,
          lng: position.longitude,
          speedKmh: speedKmh,
          accuracy: position.accuracy,
          mockLocation: isMock,
        );
      } catch (e) {
        debugPrint('RideSessionNotifier heartbeat error: $e');
      }
    });
  }

  void _stopTimers() {
    _heartbeatTimer?.cancel();
    _elapsedTimer?.cancel();
    _heartbeatTimer = null;
    _elapsedTimer = null;
  }

  void _watchForReconnect() {
    _connectivitySub?.cancel();
    _connectivitySub = Connectivity().onConnectivityChanged.listen((results) async {
      final online = results.any((r) => r != ConnectivityResult.none);
      if (!online || _pendingQrToken == null) return;
      if (state.phase != RidePhase.awaitingNetwork) {
        _clearPendingQr();
        return;
      }
      // Reconnected — retry the scan once.
      final token = _pendingQrToken!;
      final cityId = _pendingCityId;
      _clearPendingQr();
      await startWithQr(token, cityId: cityId);
    });
  }

  void _clearPendingQr() {
    _pendingQrToken = null;
    _pendingCityId = null;
    _connectivitySub?.cancel();
    _connectivitySub = null;
  }

  Future<void> _saveSummary(int pts, double co2, List<String> stamps, String message) async {
    try {
      final uid = _backend.currentUid;
      if (uid == null) return;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('${uid}_$_summaryKey', jsonEncode({
        'pointsEarned': pts,
        'co2SavedKg': co2,
        'stamps': stamps,
        'statusMessage': message,
        'savedAt': DateTime.now().toIso8601String(),
      }));
    } catch (e) {
      debugPrint('RideSessionNotifier._saveSummary error: $e');
    }
  }

  Future<void> _clearPersistedSummary() async {
    try {
      final uid = _backend.currentUid;
      if (uid == null) return;
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('${uid}_$_summaryKey');
    } catch (e) {
      debugPrint('RideSessionNotifier._clearPersistedSummary error: $e');
    }
  }

  String _friendlyError(Object e) {
    if (e is BackendHttpException) {
      try {
        final body = jsonDecode(e.body) as Map?;
        return (body?['message'] ?? body?['error'] ?? 'Request failed') as String;
      } catch (_) {
        return e.body.isNotEmpty ? e.body : 'Request failed (${e.statusCode})';
      }
    }
    if (e is BackendAuthException) return 'Please sign in again.';
    if (e is BackendRateLimitException) return e.message;
    return 'Something went wrong. Please try again.';
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

final rideSessionProvider =
    StateNotifierProvider<RideSessionNotifier, RideSessionState>(
      (ref) => RideSessionNotifier(BackendService()),
    );

/// Auto-restore ride on app start.
/// Uses ref.listen so restore fires exactly once when the city transitions
/// from null to a loaded value — avoids the race where city loads after
/// the provider initialises and restore is never called.
final rideRestoreProvider = Provider<void>((ref) {
  bool restored = false;
  ref.listen(activeCityProvider, (_, city) {
    if (city != null && !restored) {
      restored = true;
      Future.microtask(() => ref.read(rideSessionProvider.notifier).restore());
    }
  });
});

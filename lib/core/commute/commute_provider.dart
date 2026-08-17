import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/metro_station.dart';
import '../../services/backend_service.dart';
import '../city/current_city_provider.dart';
import 'commute_detector.dart';
import 'ride_verification.dart';
import 'commute_session.dart';

class CommuteNotifier extends StateNotifier<CommuteSessionState> {
  final BackendService _backend;
  final CommuteDetector _detector;
  StreamSubscription<CommuteSignal>? _signalSub;
  Timer? _heartbeatTimer;
  List<MetroStation> _stations = const [];
  bool _started = false;
  bool? _lastCompletionVerified;

  bool? get lastCompletionVerified => _lastCompletionVerified;

  CommuteNotifier(this._backend, this._detector)
    : super(const CommuteSessionState());

  Future<void> startMonitoring({
    required List<MetroStation> stations,
    String? cityId,
  }) async {
    if (_started) return;
    _started = true;
    _stations = stations;
    await restoreActiveSession(stations: stations);
    if (!state.isActive) {
      state = state.copyWith(phase: CommutePhase.detecting);
    }
    _signalSub = _detector.signals.listen((signal) {
      state = state.copyWith(
        phase:
            state.isActive
                ? CommutePhase.active
                : signal.isHighConfidence
                ? CommutePhase.confirmed
                : CommutePhase.detecting,
        confidenceScore: signal.confidenceScore,
        vibrationScore: signal.vibrationScore,
        speedKmh: signal.speedKmh,
        station: signal.station,
      );
    });
    _detector.start(stations: stations);
  }

  Future<bool> restoreActiveSession({
    List<MetroStation> stations = const [],
  }) async {
    try {
      final data = await _backend.getActiveCommuteSession();
      final raw = data['session'];
      if (raw is! Map) return false;
      final session = Map<String, dynamic>.from(raw);
      if (session['status'] != 'active' || session['rewardsEligible'] != true) {
        return false;
      }
      final stationId = session['stationId'] as String?;
      MetroStation? station;
      for (final candidate in stations) {
        if (candidate.id == stationId) {
          station = candidate;
          break;
        }
      }
      state = state.copyWith(
        phase: CommutePhase.active,
        sessionId: session['id'] as String?,
        confidenceScore: (session['confidenceScore'] as num?)?.toDouble() ?? 1,
        vibrationScore: (session['vibrationScore'] as num?)?.toDouble() ?? 0,
        speedKmh: (session['speedKmh'] as num?)?.toDouble(),
        station: station,
        startedAt: DateTime.tryParse(session['startedAt'] as String? ?? ''),
        rewardsEligible: true,
        lastHeartbeatAt: DateTime.tryParse(
          session['lastHeartbeatAt'] as String? ?? '',
        ),
        validHeartbeatCount:
            (session['validHeartbeatCount'] as num?)?.toInt() ?? 0,
      );
      await _sendHeartbeat();
      _startHeartbeatTimer();
      return true;
    } catch (error) {
      debugPrint('Commute session restore failed: $error');
      return false;
    }
  }

  Future<bool> startManual({
    String? cityId,
    required RideVerification ticketVerification,
  }) async {
    return _openBackendSession(
      cityId: cityId,
      phase: 'active',
      ticketVerification: ticketVerification,
    );
  }

  Future<bool> acceptDetected({
    String? cityId,
    required RideVerification ticketVerification,
  }) async {
    return _openBackendSession(
      cityId: cityId,
      phase: 'active',
      ticketVerification: ticketVerification,
    );
  }

  Future<bool> _openBackendSession({
    String? cityId,
    required String phase,
    required RideVerification ticketVerification,
  }) async {
    final previous = state;
    try {
      final location = await _detector.captureHeartbeat(
        _stations,
        vibrationScore: state.vibrationScore,
      );
      if (location == null || !location.hasLocationEvidence) {
        state = previous.copyWith(
          error:
              'A trusted, high-accuracy station location is required to start.',
        );
        return false;
      }
      final data = await _backend.submitCommuteSignal(
        confidenceScore: state.confidenceScore <= 0 ? 1 : state.confidenceScore,
        vibrationScore: state.vibrationScore,
        speedKmh: state.speedKmh,
        stationId: state.station?.id,
        cityId: cityId,
        phase: phase,
        ticketVerification: ticketVerification,
        location: location,
      );
      final raw = data['session'];
      final session =
          raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
      final eligible =
          session['rewardsEligible'] == true && session['status'] == 'active';
      if (!eligible) {
        state = previous.copyWith(
          error: 'Scan an official station QR code to activate Ride Mode.',
        );
        return false;
      }
      state = state.copyWith(
        phase: CommutePhase.active,
        sessionId: session['id'] as String?,
        startedAt:
            DateTime.tryParse(session['startedAt'] as String? ?? '') ??
            DateTime.now(),
        rewardsEligible: true,
        lastHeartbeatAt: DateTime.tryParse(
          session['lastHeartbeatAt'] as String? ?? '',
        ),
        validHeartbeatCount:
            (session['validHeartbeatCount'] as num?)?.toInt() ?? 1,
      );
      _startHeartbeatTimer();
      return true;
    } catch (error) {
      debugPrint('Commute session open failed: $error');
      state = previous.copyWith(error: error.toString());
      return false;
    }
  }

  Future<bool> end({String? endStationId}) async {
    final sessionId = state.sessionId;
    if (sessionId == null) return false;
    final previous = state;
    try {
      await _sendHeartbeat();
      state = state.copyWith(phase: CommutePhase.ending);
      final result = await _backend.endCommuteSession(
        sessionId: sessionId,
        endStationId: endStationId,
      );
      _lastCompletionVerified = result['verifiedCompletion'] == true;
      state = const CommuteSessionState(phase: CommutePhase.detecting);
      _heartbeatTimer?.cancel();
      return true;
    } catch (error) {
      debugPrint('Commute session end failed: $error');
      state = previous.copyWith(
        error: 'Reconnect and try again to end Ride Mode.',
      );
      return false;
    }
  }

  void dismiss() {
    state = const CommuteSessionState(phase: CommutePhase.detecting);
  }

  void _startHeartbeatTimer() {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _sendHeartbeat();
    });
  }

  Future<void> _sendHeartbeat() async {
    final sessionId = state.sessionId;
    if (sessionId == null || state.phase == CommutePhase.ending) return;
    final signal = await _detector.captureHeartbeat(
      _stations,
      vibrationScore: state.vibrationScore,
    );
    if (signal == null || !signal.hasLocationEvidence) {
      state = state.copyWith(
        rewardsEligible: false,
        error: 'Points paused until Ride Mode can verify your location.',
      );
      return;
    }
    try {
      final data = await _backend.sendCommuteHeartbeat(
        sessionId: sessionId,
        signal: signal,
      );
      state = state.copyWith(
        rewardsEligible: data['rewardsEligible'] == true,
        lastHeartbeatAt: DateTime.now(),
        validHeartbeatCount:
            (data['validHeartbeatCount'] as num?)?.toInt() ??
            state.validHeartbeatCount,
      );
    } catch (error) {
      debugPrint('Commute heartbeat failed: $error');
      state = state.copyWith(
        rewardsEligible: false,
        error: 'Points paused while Ride Mode reconnects.',
      );
    }
  }

  @override
  void dispose() {
    _signalSub?.cancel();
    _heartbeatTimer?.cancel();
    _detector.dispose();
    super.dispose();
  }
}

final commuteProvider =
    StateNotifierProvider<CommuteNotifier, CommuteSessionState>((ref) {
      return CommuteNotifier(BackendService(), CommuteDetector());
    });

final commuteAutoStartProvider = Provider<void>((ref) {
  final city = ref.watch(activeCityProvider);
  final stations = ref.watch(cityStationsProvider);
  if (city != null) {
    Future.microtask(() {
      ref
          .read(commuteProvider.notifier)
          .startMonitoring(stations: stations, cityId: city.id);
    });
  }
});

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
  bool _started = false;

  CommuteNotifier(this._backend, this._detector)
    : super(const CommuteSessionState());

  Future<void> startMonitoring({
    required List<MetroStation> stations,
    String? cityId,
  }) async {
    if (_started) return;
    _started = true;
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
      if (signal.isHighConfidence) {
        _backend
            .submitCommuteSignal(
              confidenceScore: signal.confidenceScore,
              vibrationScore: signal.vibrationScore,
              speedKmh: signal.speedKmh,
              stationId: signal.station?.id,
              cityId: cityId,
              phase: 'confirmed',
            )
            .catchError((error) {
              debugPrint('Commute signal submit failed: $error');
              return <String, dynamic>{};
            });
      }
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
      );
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
      final data = await _backend.submitCommuteSignal(
        confidenceScore: state.confidenceScore <= 0 ? 1 : state.confidenceScore,
        vibrationScore: state.vibrationScore,
        speedKmh: state.speedKmh,
        stationId: state.station?.id,
        cityId: cityId,
        phase: phase,
        ticketVerification: ticketVerification,
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
      );
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
    state = state.copyWith(phase: CommutePhase.ending);
    try {
      await _backend.endCommuteSession(
        sessionId: sessionId,
        endStationId: endStationId,
      );
      state = const CommuteSessionState(phase: CommutePhase.detecting);
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

  @override
  void dispose() {
    _signalSub?.cancel();
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

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
    state = state.copyWith(phase: CommutePhase.detecting);
    _signalSub = _detector.signals.listen((signal) {
      state = state.copyWith(
        phase:
            signal.isHighConfidence
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

  Future<void> startManual({
    String? cityId,
    required RideVerification ticketVerification,
  }) async {
    // Show verifying spinner before touching the backend.
    state = state.copyWith(phase: CommutePhase.verifying, confidenceScore: 1);
    await _openBackendSession(cityId: cityId, phase: 'active', ticketVerification: ticketVerification);
  }

  Future<void> acceptDetected({
    String? cityId,
    required RideVerification ticketVerification,
  }) async {
    state = state.copyWith(phase: CommutePhase.verifying);
    await _openBackendSession(cityId: cityId, phase: 'active', ticketVerification: ticketVerification);
  }

  Future<void> _openBackendSession({
    String? cityId,
    required String phase,
    required RideVerification ticketVerification,
  }) async {
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
      final session = data['session'] as Map<String, dynamic>?;
      final sessionId = session?['id'] as String?;
      final confirmed = data['confirmed'] == true;

      if (confirmed && sessionId != null) {
        // Backend confirmed — now safe to show as active.
        state = state.copyWith(
          phase: CommutePhase.active,
          sessionId: sessionId,
          startedAt: DateTime.now(),
        );
      } else {
        // Backend rejected or returned no session — roll back to detecting.
        state = state.copyWith(
          phase: CommutePhase.detecting,
          error: 'Could not verify your ride. Please rescan the station QR.',
        );
      }
    } catch (error) {
      debugPrint('Commute session open failed: $error');
      // Any exception (4xx, network) rolls back to detecting with an error message.
      state = state.copyWith(
        phase: CommutePhase.detecting,
        error: error.toString(),
      );
    }
  }

  Future<void> end({String? endStationId}) async {
    final sessionId = state.sessionId;
    state = state.copyWith(phase: CommutePhase.ending);
    if (sessionId != null) {
      try {
        await _backend.endCommuteSession(
          sessionId: sessionId,
          endStationId: endStationId,
        );
      } catch (error) {
        debugPrint('Commute session end failed: $error');
      }
    }
    state = const CommuteSessionState();
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

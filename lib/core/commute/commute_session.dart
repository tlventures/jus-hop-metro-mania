import '../../models/metro_station.dart';

enum CommutePhase { idle, detecting, confirmed, verifying, active, ending }

class CommuteSignal {
  final double confidenceScore;
  final double vibrationScore;
  final double? speedKmh;
  final MetroStation? station;

  const CommuteSignal({
    required this.confidenceScore,
    required this.vibrationScore,
    this.speedKmh,
    this.station,
  });

  bool get isHighConfidence => confidenceScore >= 0.75;
}

class CommuteSessionState {
  final CommutePhase phase;
  final String? sessionId;
  final double confidenceScore;
  final double vibrationScore;
  final double? speedKmh;
  final MetroStation? station;
  final DateTime? startedAt;
  final String? error;

  const CommuteSessionState({
    this.phase = CommutePhase.idle,
    this.sessionId,
    this.confidenceScore = 0,
    this.vibrationScore = 0,
    this.speedKmh,
    this.station,
    this.startedAt,
    this.error,
  });

  bool get isVisible =>
      phase == CommutePhase.confirmed ||
      phase == CommutePhase.verifying ||
      phase == CommutePhase.active;
  bool get isActive => phase == CommutePhase.active;
  bool get isVerifying => phase == CommutePhase.verifying;

  CommuteSessionState copyWith({
    CommutePhase? phase,
    String? sessionId,
    double? confidenceScore,
    double? vibrationScore,
    double? speedKmh,
    MetroStation? station,
    DateTime? startedAt,
    String? error,
  }) {
    return CommuteSessionState(
      phase: phase ?? this.phase,
      sessionId: sessionId ?? this.sessionId,
      confidenceScore: confidenceScore ?? this.confidenceScore,
      vibrationScore: vibrationScore ?? this.vibrationScore,
      speedKmh: speedKmh ?? this.speedKmh,
      station: station ?? this.station,
      startedAt: startedAt ?? this.startedAt,
      error: error,
    );
  }
}

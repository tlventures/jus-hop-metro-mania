import '../../models/metro_station.dart';

enum CommutePhase { idle, detecting, confirmed, active, ending }

class CommuteSignal {
  final double confidenceScore;
  final double vibrationScore;
  final double? speedKmh;
  final MetroStation? station;
  final double? latitude;
  final double? longitude;
  final double? accuracyMeters;
  final DateTime? recordedAt;
  final bool deviceTrusted;

  const CommuteSignal({
    required this.confidenceScore,
    required this.vibrationScore,
    this.speedKmh,
    this.station,
    this.latitude,
    this.longitude,
    this.accuracyMeters,
    this.recordedAt,
    this.deviceTrusted = false,
  });

  bool get isHighConfidence => confidenceScore >= 0.75;
  bool get hasLocationEvidence =>
      latitude != null &&
      longitude != null &&
      accuracyMeters != null &&
      recordedAt != null &&
      deviceTrusted;

  Map<String, dynamic> toHeartbeatJson() => {
    'lat': latitude,
    'lng': longitude,
    'accuracyMeters': accuracyMeters,
    if (speedKmh != null) 'speedKmh': speedKmh,
    'recordedAt': recordedAt?.toUtc().toIso8601String(),
    'deviceTrusted': deviceTrusted,
  };
}

class CommuteSessionState {
  final CommutePhase phase;
  final String? sessionId;
  final double confidenceScore;
  final double vibrationScore;
  final double? speedKmh;
  final MetroStation? station;
  final DateTime? startedAt;
  final bool rewardsEligible;
  final DateTime? lastHeartbeatAt;
  final int validHeartbeatCount;
  final String? error;

  const CommuteSessionState({
    this.phase = CommutePhase.idle,
    this.sessionId,
    this.confidenceScore = 0,
    this.vibrationScore = 0,
    this.speedKmh,
    this.station,
    this.startedAt,
    this.rewardsEligible = false,
    this.lastHeartbeatAt,
    this.validHeartbeatCount = 0,
    this.error,
  });

  bool get isVisible =>
      phase == CommutePhase.confirmed || phase == CommutePhase.active;
  bool get isActive => phase == CommutePhase.active && rewardsEligible;

  CommuteSessionState copyWith({
    CommutePhase? phase,
    String? sessionId,
    bool clearSessionId = false,
    double? confidenceScore,
    double? vibrationScore,
    double? speedKmh,
    MetroStation? station,
    DateTime? startedAt,
    bool? rewardsEligible,
    DateTime? lastHeartbeatAt,
    int? validHeartbeatCount,
    String? error,
  }) {
    return CommuteSessionState(
      phase: phase ?? this.phase,
      sessionId: clearSessionId ? null : sessionId ?? this.sessionId,
      confidenceScore: confidenceScore ?? this.confidenceScore,
      vibrationScore: vibrationScore ?? this.vibrationScore,
      speedKmh: speedKmh ?? this.speedKmh,
      station: station ?? this.station,
      startedAt: startedAt ?? this.startedAt,
      rewardsEligible: rewardsEligible ?? this.rewardsEligible,
      lastHeartbeatAt: lastHeartbeatAt ?? this.lastHeartbeatAt,
      validHeartbeatCount: validHeartbeatCount ?? this.validHeartbeatCount,
      error: error,
    );
  }
}

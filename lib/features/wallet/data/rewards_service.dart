// lib/features/wallet/data/rewards_service.dart

import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../config/api_config.dart';

class RewardsAuthException implements Exception {
  const RewardsAuthException();
  @override
  String toString() => 'Please sign in to continue.';
}

class RewardsApiException implements Exception {
  final int statusCode;
  final String message;
  const RewardsApiException(this.statusCode, this.message);
  @override
  String toString() => 'Rewards API error ($statusCode): $message';
}

class EarnResult {
  final int pointsAwarded;
  final String source;
  final int newBalance;
  final int dayCapRemainingSource;
  final int dayCapRemainingTotal;
  final bool duplicate;

  const EarnResult({
    required this.pointsAwarded,
    required this.source,
    required this.newBalance,
    required this.dayCapRemainingSource,
    required this.dayCapRemainingTotal,
    required this.duplicate,
  });

  factory EarnResult.fromJson(Map<String, dynamic> j) => EarnResult(
        pointsAwarded: (j['points_awarded'] as num?)?.toInt() ?? 0,
        source: j['source'] as String? ?? '',
        newBalance: (j['new_balance'] as num?)?.toInt() ?? 0,
        dayCapRemainingSource: (j['day_cap_remaining_source'] as num?)?.toInt() ?? 0,
        dayCapRemainingTotal: (j['day_cap_remaining_total'] as num?)?.toInt() ?? 0,
        duplicate: j['duplicate'] == true,
      );
}

class StreakStatus {
  final int currentDay;
  final int longestDay;
  final bool canClaim;
  final int nextRewardPoints;
  final DateTime? nextClaimAt;
  const StreakStatus({
    required this.currentDay,
    required this.longestDay,
    required this.canClaim,
    required this.nextRewardPoints,
    this.nextClaimAt,
  });
  factory StreakStatus.fromJson(Map<String, dynamic> j) => StreakStatus(
        currentDay: (j['current_day'] as num?)?.toInt() ?? 0,
        longestDay: (j['longest_day'] as num?)?.toInt() ?? 0,
        canClaim: j['can_claim'] == true,
        nextRewardPoints: (j['next_reward_points'] as num?)?.toInt() ?? 5,
        nextClaimAt: j['next_claim_at'] != null
            ? DateTime.tryParse(j['next_claim_at'] as String)
            : null,
      );
}

class StreakClaimResult extends StreakStatus {
  final int pointsAwarded;
  const StreakClaimResult({
    required this.pointsAwarded,
    required super.currentDay,
    required super.longestDay,
    required super.canClaim,
    required super.nextRewardPoints,
    super.nextClaimAt,
  });
  factory StreakClaimResult.fromJson(Map<String, dynamic> j) => StreakClaimResult(
        pointsAwarded: (j['points_awarded'] as num?)?.toInt() ?? 0,
        currentDay: (j['current_day'] as num?)?.toInt() ?? 0,
        longestDay: (j['longest_day'] as num?)?.toInt() ?? 0,
        canClaim: j['can_claim'] == true,
        nextRewardPoints: (j['next_reward_points'] as num?)?.toInt() ?? 5,
        nextClaimAt: j['next_claim_at'] != null
            ? DateTime.tryParse(j['next_claim_at'] as String)
            : null,
      );
}

class ReferralCode {
  final String code;
  final String shareMessage;
  final int referrerReward;
  final int referredReward;
  const ReferralCode({
    required this.code,
    required this.shareMessage,
    required this.referrerReward,
    required this.referredReward,
  });
  factory ReferralCode.fromJson(Map<String, dynamic> j) => ReferralCode(
        code: j['code'] as String,
        shareMessage: j['share_message'] as String? ?? '',
        referrerReward: (j['referrer_reward'] as num?)?.toInt() ?? 100,
        referredReward: (j['referred_reward'] as num?)?.toInt() ?? 50,
      );
}

class RewardsService {
  final http.Client _client;
  RewardsService({http.Client? client}) : _client = client ?? http.Client();

  Uri _uri(String p) => Uri.parse('${ApiConfig.baseUrl}$p');

  Future<Map<String, String>> _headers() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw const RewardsAuthException();
    String? token;
    try {
      token = await user.getIdToken();
    } catch (_) {}
    return {
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  Future<EarnResult> earn({
    required String source,
    required String eventId,
    Map<String, dynamic>? metadata,
  }) async {
    final r = await _client.post(
      _uri('/api/v1/rewards/earn'),
      headers: await _headers(),
      body: jsonEncode({
        'source': source,
        'event_id': eventId,
        if (metadata != null) 'metadata': metadata,
      }),
    );
    if (r.statusCode == 401 || r.statusCode == 403) throw const RewardsAuthException();
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw RewardsApiException(r.statusCode, _extract(r.body));
    }
    return EarnResult.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
  }

  Future<StreakStatus> getStreak() async {
    final r = await _client.get(_uri('/api/v1/rewards/streak'), headers: await _headers());
    if (r.statusCode == 401 || r.statusCode == 403) throw const RewardsAuthException();
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw RewardsApiException(r.statusCode, _extract(r.body));
    }
    return StreakStatus.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
  }

  Future<StreakClaimResult> claimStreak() async {
    final r = await _client.post(_uri('/api/v1/rewards/streak/claim'), headers: await _headers());
    if (r.statusCode == 401 || r.statusCode == 403) throw const RewardsAuthException();
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw RewardsApiException(r.statusCode, _extract(r.body));
    }
    return StreakClaimResult.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
  }

  Future<ReferralCode> getReferralCode() async {
    final r = await _client.get(
      _uri('/api/v1/rewards/referral/code'),
      headers: await _headers(),
    );
    if (r.statusCode == 401 || r.statusCode == 403) throw const RewardsAuthException();
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw RewardsApiException(r.statusCode, _extract(r.body));
    }
    return ReferralCode.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
  }

  Future<void> applyReferral(String referrerCode) async {
    final r = await _client.post(
      _uri('/api/v1/rewards/referral/apply'),
      headers: await _headers(),
      body: jsonEncode({'referrer_code': referrerCode.toUpperCase()}),
    );
    if (r.statusCode == 401 || r.statusCode == 403) throw const RewardsAuthException();
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw RewardsApiException(r.statusCode, _extract(r.body));
    }
  }

  String _extract(String body) {
    try {
      final j = jsonDecode(body);
      if (j is Map && j['detail'] is String) return j['detail'] as String;
    } catch (_) {}
    if (kDebugMode) debugPrint('rewards raw body: $body');
    return 'Request failed';
  }
}

// lib/features/wallet/data/promo_service.dart

import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../../config/api_config.dart';

class PromoAuthRequiredException implements Exception {
  const PromoAuthRequiredException();
  @override
  String toString() => 'Please sign in to continue.';
}

class PromoApiException implements Exception {
  final int statusCode;
  final String message;
  const PromoApiException(this.statusCode, this.message);
  @override
  String toString() => 'Wallet API error ($statusCode): $message';
}

class WalletBalance {
  final int points;
  final double inrEquivalent;
  final int pointsPerInr;
  final DateTime? nextExpiryAt;
  final int nextExpiryPoints;

  const WalletBalance({
    required this.points,
    required this.inrEquivalent,
    required this.pointsPerInr,
    this.nextExpiryAt,
    this.nextExpiryPoints = 0,
  });

  factory WalletBalance.fromJson(Map<String, dynamic> j) => WalletBalance(
        points: (j['points'] as num?)?.toInt() ?? 0,
        inrEquivalent: double.tryParse('${j['inr_equivalent'] ?? '0'}') ?? 0,
        pointsPerInr: (j['points_per_inr'] as num?)?.toInt() ?? 10,
        nextExpiryAt: j['next_expiry_at'] != null
            ? DateTime.tryParse(j['next_expiry_at'] as String)
            : null,
        nextExpiryPoints: (j['next_expiry_points'] as num?)?.toInt() ?? 0,
      );
}

class PromoCodeItem {
  final String code;
  final double valueInr;
  final int pointsBurnt;
  final String status; // ACTIVE / USED / EXPIRED / CANCELLED
  final DateTime createdAt;
  final DateTime expiresAt;
  final DateTime? redeemedAt;

  const PromoCodeItem({
    required this.code,
    required this.valueInr,
    required this.pointsBurnt,
    required this.status,
    required this.createdAt,
    required this.expiresAt,
    this.redeemedAt,
  });

  factory PromoCodeItem.fromJson(Map<String, dynamic> j) => PromoCodeItem(
        code: j['code'] as String,
        valueInr: double.tryParse('${j['value_inr'] ?? '0'}') ?? 0,
        pointsBurnt: (j['points_burnt'] as num?)?.toInt() ?? 0,
        status: j['status'] as String? ?? 'ACTIVE',
        createdAt: DateTime.parse(j['created_at'] as String),
        expiresAt: DateTime.parse(j['expires_at'] as String),
        redeemedAt: j['redeemed_at'] != null
            ? DateTime.tryParse(j['redeemed_at'] as String)
            : null,
      );

  bool get isActive => status == 'ACTIVE' && DateTime.now().isBefore(expiresAt);
}

class PromoService {
  final http.Client _client;
  PromoService({http.Client? client}) : _client = client ?? http.Client();

  Uri _uri(String p) => Uri.parse('${ApiConfig.baseUrl}$p');

  Future<Map<String, String>> _headers() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw const PromoAuthRequiredException();
    String? token;
    try {
      token = await user.getIdToken();
    } catch (_) {}
    return {
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
    };
  }

  Future<WalletBalance> fetchBalance() async {
    final r = await _client.get(_uri('/api/v1/wallet/balance'), headers: await _headers());
    if (r.statusCode == 401 || r.statusCode == 403) throw const PromoAuthRequiredException();
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw PromoApiException(r.statusCode, _extract(r.body));
    }
    return WalletBalance.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
  }

  Future<PromoCodeItem> redeem(int pointsToRedeem) async {
    final r = await _client.post(
      _uri('/api/v1/wallet/redeem'),
      headers: await _headers(),
      body: jsonEncode({'points_to_redeem': pointsToRedeem}),
    );
    if (r.statusCode == 401 || r.statusCode == 403) throw const PromoAuthRequiredException();
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw PromoApiException(r.statusCode, _extract(r.body));
    }
    return PromoCodeItem.fromJson(jsonDecode(r.body) as Map<String, dynamic>);
  }

  Future<List<PromoCodeItem>> listCodes() async {
    final r = await _client.get(_uri('/api/v1/wallet/codes'), headers: await _headers());
    if (r.statusCode == 401 || r.statusCode == 403) throw const PromoAuthRequiredException();
    if (r.statusCode < 200 || r.statusCode >= 300) {
      if (kDebugMode) debugPrint('promo/listCodes ${r.statusCode}: ${r.body}');
      return const [];
    }
    final body = jsonDecode(r.body) as Map<String, dynamic>;
    final list = (body['codes'] as List?) ?? const [];
    return list
        .map((e) => PromoCodeItem.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  String _extract(String body) {
    try {
      final j = jsonDecode(body);
      if (j is Map && j['detail'] is String) return j['detail'] as String;
    } catch (_) {}
    return 'Request failed';
  }
}

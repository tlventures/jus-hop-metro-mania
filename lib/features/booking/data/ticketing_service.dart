// lib/features/booking/data/ticketing_service.dart

import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../../../config/api_config.dart';
import '../domain/ticketing_models.dart';

class TicketingAuthRequiredException implements Exception {
  const TicketingAuthRequiredException();
  @override
  String toString() => 'Please sign in to continue.';
}

class TicketingApiException implements Exception {
  final int statusCode;
  final String message;
  const TicketingApiException(this.statusCode, this.message);
  @override
  String toString() => 'Ticketing API error ($statusCode): $message';
}

class TicketingService {
  final http.Client _client;
  static const _uuid = Uuid();

  TicketingService({http.Client? client}) : _client = client ?? http.Client();

  Uri _uri(String path) {
    // Booking is fulfilled by the ONDC/Beckn backend, NOT the app backend.
    final url = '${ApiConfig.ondcBaseUrl}$path';
    assert(url.startsWith('https://'), 'Ticketing API must be HTTPS: $url');
    if (!url.startsWith('https://')) {
      throw StateError('Refusing to send booking traffic over non-HTTPS URL.');
    }
    return Uri.parse(url);
  }

  Future<Map<String, String>> _headers({required String idempotencyKey}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw const TicketingAuthRequiredException();
    }
    String? token;
    try {
      token = await user.getIdToken();
    } catch (e) {
      if (kDebugMode) debugPrint('TicketingService: could not get Firebase token: $e');
    }
    if (token == null || token.isEmpty) {
      throw const TicketingAuthRequiredException();
    }
    return {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $token',
      'Idempotency-Key': idempotencyKey,
    };
  }

  Future<http.Response> _postJson(
    Uri url, {
    required String idempotencyKey,
    required Map<String, dynamic> body,
    required String opLabel,
  }) async {
    final headers = await _headers(idempotencyKey: idempotencyKey);
    if (kDebugMode) debugPrint('TicketingService.$opLabel POST $url');
    final response = await _client.post(url, headers: headers, body: jsonEncode(body));
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const TicketingAuthRequiredException();
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (kDebugMode) {
        debugPrint('TicketingService.$opLabel failed: ${response.statusCode}');
      }
      throw TicketingApiException(response.statusCode, _extractErr(response.body));
    }
    return response;
  }

  String _extractErr(String body) {
    try {
      final j = jsonDecode(body);
      if (j is Map && j['detail'] is String) return j['detail'] as String;
      if (j is Map && j['error'] is Map && j['error']['message'] is String) {
        return j['error']['message'] as String;
      }
    } catch (_) {}
    return 'Request failed';
  }

  /// Search available metro ticket options between origin and destination stations.
  Future<Map<String, dynamic>> searchRoutes({
    required String originStationId,
    required String destinationStationId,
    String cityCode = 'std:040',
  }) async {
    final transactionId = _uuid.v4();
    final response = await _postJson(
      _uri('/api/v1/search'),
      idempotencyKey: 'search:$transactionId',
      body: {
        'origin_station_id': originStationId,
        'destination_station_id': destinationStationId,
        'city_code': cityCode,
        'transaction_id': transactionId,
      },
      opLabel: 'searchRoutes',
    );
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    json['transaction_id'] ??= transactionId;
    return json;
  }

  Future<Map<String, dynamic>> selectTicket({
    required String transactionId,
    required String itemId,
    int passengerCount = 1,
    int rewardPointsToRedeem = 0,
    String? promoCode,
  }) async {
    final response = await _postJson(
      _uri('/api/v1/select'),
      idempotencyKey: 'select:$transactionId'
          '${promoCode == null ? '' : ':$promoCode'}',
      body: {
        'transaction_id': transactionId,
        'item_id': itemId,
        'provider_id': 'P1',
        'passenger_count': passengerCount,
        'reward_points_to_redeem': rewardPointsToRedeem,
        if (promoCode != null) 'promo_code': promoCode,
      },
      opLabel: 'selectTicket',
    );
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> initTicket({
    required String transactionId,
    required String itemId,
    required String passengerName,
    required String passengerPhone,
    String? passengerEmail,
    int passengerCount = 1,
  }) async {
    final response = await _postJson(
      _uri('/api/v1/init'),
      idempotencyKey: 'init:$transactionId',
      body: {
        'transaction_id': transactionId,
        'item_id': itemId,
        'provider_id': 'P1',
        'passenger_name': passengerName,
        'passenger_phone': passengerPhone,
        'passenger_email': passengerEmail,
        'passenger_count': passengerCount,
      },
      opLabel: 'initTicket',
    );
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Create a Razorpay order server-side. Amount is derived from the txn quote;
  /// client cannot influence it. Returns { order_id, amount, currency, key_id }.
  Future<Map<String, dynamic>> createRazorpayOrder({
    required String transactionId,
    required String itemId,
    int passengerCount = 1,
  }) async {
    final response = await _postJson(
      _uri('/api/v1/payments/razorpay/order'),
      idempotencyKey: 'rzp_order:$transactionId',
      body: {
        'transaction_id': transactionId,
        'item_id': itemId,
        'provider_id': 'P1',
        'passenger_count': passengerCount,
      },
      opLabel: 'createRazorpayOrder',
    );
    return jsonDecode(response.body) as Map<String, dynamic>;
  }

  /// Verify Razorpay payment server-side (HMAC signature), then send /confirm
  /// to the BPP. Returns the signed MetroTicket the server issued.
  Future<MetroTicket> confirmPayment({
    required String transactionId,
    required String razorpayOrderId,
    required String razorpayPaymentId,
    required String razorpaySignature,
    required String itemId,
    int passengerCount = 1,
  }) async {
    final response = await _postJson(
      _uri('/api/v1/confirm'),
      idempotencyKey: 'confirm:$transactionId',
      body: {
        'transaction_id': transactionId,
        'razorpay_order_id': razorpayOrderId,
        'razorpay_payment_id': razorpayPaymentId,
        'razorpay_signature': razorpaySignature,
        'item_id': itemId,
        'provider_id': 'P1',
        'passenger_count': passengerCount,
      },
      opLabel: 'confirmPayment',
    );
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    // Server MUST return a signed ticket. No client-side fabrication ever.
    final ticketJson = (json['ticket'] as Map?)?.cast<String, dynamic>() ?? json;
    return MetroTicket.fromJson(ticketJson);
  }
}

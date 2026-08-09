// lib/features/booking/domain/ticketing_models.dart

import 'package:flutter/foundation.dart';

@immutable
class RouteOption {
  final String id; // e.g. "I1" for Single Journey, "I2" for Return Journey
  final String title;
  final String type; // "SJT" or "RJT"
  final double fare;
  final String currency;
  final int totalDurationMinutes;
  final int totalStops;
  final String providerId;

  const RouteOption({
    required this.id,
    required this.title,
    required this.type,
    required this.fare,
    this.currency = 'INR',
    required this.totalDurationMinutes,
    required this.totalStops,
    this.providerId = 'P1',
  });

  factory RouteOption.fromJson(Map<String, dynamic> json) {
    return RouteOption(
      id: json['id'] as String? ?? 'I1',
      title: json['title'] as String? ?? 'Single Journey Ticket (SJT)',
      type: json['type'] as String? ?? 'SJT',
      fare: (json['fare'] as num?)?.toDouble() ?? 35.0,
      currency: json['currency'] as String? ?? 'INR',
      totalDurationMinutes: (json['duration_minutes'] as num?)?.toInt() ?? 24,
      totalStops: (json['total_stops'] as num?)?.toInt() ?? 8,
      providerId: json['provider_id'] as String? ?? 'P1',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'type': type,
        'fare': fare,
        'currency': currency,
        'duration_minutes': totalDurationMinutes,
        'total_stops': totalStops,
        'provider_id': providerId,
      };
}

@immutable
class MetroTicket {
  final String ticketId;
  final String transactionId;
  final String orderId;
  final String originStation;
  final String destinationStation;
  final String ticketType;
  final int passengerCount;
  final double totalFare;
  final int pointsEarned;
  final String qrPayload;
  final DateTime issuedAt;
  final DateTime expiresAt;
  final String status;

  const MetroTicket({
    required this.ticketId,
    required this.transactionId,
    required this.orderId,
    required this.originStation,
    required this.destinationStation,
    required this.ticketType,
    required this.passengerCount,
    required this.totalFare,
    this.pointsEarned = 0,
    required this.qrPayload,
    required this.issuedAt,
    required this.expiresAt,
    required this.status,
  });

  /// Strict parser: rejects the payload unless the server issued a real,
  /// signed ticket. No client-side defaults for identity or expiry — a missing
  /// field is a hard error, not something to invent.
  factory MetroTicket.fromJson(Map<String, dynamic> json) {
    String req(String key) {
      final v = json[key];
      if (v is! String || v.isEmpty) {
        throw FormatException('MetroTicket: server response missing "$key"');
      }
      return v;
    }

    DateTime reqTs(String key) {
      final v = json[key];
      if (v is! String || v.isEmpty) {
        throw FormatException('MetroTicket: server response missing "$key"');
      }
      return DateTime.parse(v);
    }

    final qr = json['qr_payload'];
    if (qr is! String || qr.isEmpty) {
      throw const FormatException('MetroTicket: server did not return a signed qr_payload');
    }

    return MetroTicket(
      ticketId: req('ticket_id'),
      transactionId: req('transaction_id'),
      orderId: req('order_id'),
      originStation: req('origin_station'),
      destinationStation: req('destination_station'),
      ticketType: req('ticket_type'),
      passengerCount: (json['passenger_count'] as num?)?.toInt() ?? 1,
      totalFare: (json['total_fare'] as num?)?.toDouble()
          ?? (json['amount_paid'] as num?)?.toDouble()
          ?? (throw const FormatException('MetroTicket: server did not return total_fare')),
      pointsEarned: (json['points_earned'] as num?)?.toInt() ?? 0,
      qrPayload: qr,
      issuedAt: reqTs('issued_at'),
      expiresAt: reqTs('expires_at'),
      status: req('status'),
    );
  }

  Map<String, dynamic> toJson() => {
        'ticket_id': ticketId,
        'transaction_id': transactionId,
        'order_id': orderId,
        'origin_station': originStation,
        'destination_station': destinationStation,
        'ticket_type': ticketType,
        'passenger_count': passengerCount,
        'total_fare': totalFare,
        'points_earned': pointsEarned,
        'qr_payload': qrPayload,
        'issued_at': issuedAt.toIso8601String(),
        'expires_at': expiresAt.toIso8601String(),
        'status': status,
      };
}

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class PendingMutation {
  final String id;
  final String method;
  final String path;
  final Map<String, String> headers;
  final Map<String, dynamic>? body;
  final DateTime createdAt;
  final int retryCount;
  final String? lastError;

  const PendingMutation({
    required this.id,
    required this.method,
    required this.path,
    required this.headers,
    required this.createdAt,
    this.body,
    this.retryCount = 0,
    this.lastError,
  });

  /// A mutation is "dead" (should be dropped, never retried again) once it has
  /// failed too many times or has been sitting in the queue past its TTL.
  /// This stops a permanently-failing request (deleted endpoint, expired auth,
  /// server-side validation error) from being retried forever and bloating the
  /// stored outbox on every connectivity event.
  bool isDead({
    int maxRetries = Outbox.maxRetries,
    Duration ttl = Outbox.ttl,
  }) {
    if (retryCount >= maxRetries) return true;
    return DateTime.now().difference(createdAt) > ttl;
  }

  PendingMutation copyWith({int? retryCount, String? lastError}) {
    return PendingMutation(
      id: id,
      method: method,
      path: path,
      headers: headers,
      body: body,
      createdAt: createdAt,
      retryCount: retryCount ?? this.retryCount,
      lastError: lastError ?? this.lastError,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'method': method,
      'path': path,
      'headers': headers,
      'body': body,
      'createdAt': createdAt.toIso8601String(),
      'retryCount': retryCount,
      'lastError': lastError,
    };
  }

  factory PendingMutation.fromJson(Map<String, dynamic> json) {
    return PendingMutation(
      id: json['id'] as String,
      method: json['method'] as String,
      path: json['path'] as String,
      headers: Map<String, String>.from(json['headers'] as Map? ?? {}),
      body:
          json['body'] == null
              ? null
              : Map<String, dynamic>.from(json['body'] as Map),
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      retryCount: (json['retryCount'] as num?)?.toInt() ?? 0,
      lastError: json['lastError'] as String?,
    );
  }
}

class Outbox {
  static const String _storageKey = 'phase56_outbox';
  static const int _maxEntries = 1000;

  /// Drop a queued mutation after this many failed flush attempts.
  static const int maxRetries = 5;

  /// Drop a queued mutation if it has not synced within this window, regardless
  /// of retry count (e.g. a device that was offline for days).
  static const Duration ttl = Duration(hours: 72);

  /// Purge dead (max-retries-exceeded or expired) mutations from storage.
  /// Returns the entries that were dropped so callers can log/telemeter them.
  Future<List<PendingMutation>> purgeDead() async {
    final current = await all();
    final dead = current.where((m) => m.isDead()).toList();
    if (dead.isEmpty) return const [];
    await replaceAll(current.where((m) => !m.isDead()).toList());
    return dead;
  }

  Future<List<PendingMutation>> all() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getStringList(_storageKey) ?? const [];
    return raw
        .map(
          (entry) => PendingMutation.fromJson(
            Map<String, dynamic>.from(jsonDecode(entry) as Map),
          ),
        )
        .toList();
  }

  Future<void> enqueue(PendingMutation mutation) async {
    final prefs = await SharedPreferences.getInstance();
    final existing = await all();
    final next = [
      ...existing.where((item) => item.id != mutation.id),
      mutation,
    ];
    final capped =
        next.length > _maxEntries
            ? next.sublist(next.length - _maxEntries)
            : next;
    await prefs.setStringList(
      _storageKey,
      capped.map((item) => jsonEncode(item.toJson())).toList(),
    );
  }

  Future<void> replaceAll(List<PendingMutation> mutations) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _storageKey,
      mutations.map((item) => jsonEncode(item.toJson())).toList(),
    );
  }

  Future<void> remove(String id) async {
    final current = await all();
    await replaceAll(current.where((item) => item.id != id).toList());
  }

  Future<int> count() async => (await all()).length;
}

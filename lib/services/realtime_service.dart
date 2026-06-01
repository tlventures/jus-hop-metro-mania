import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;

import '../config/api_config.dart';
import 'backend_service.dart';

/// Event types pushed from the WebSocket server.
enum RealtimeEventType {
  disruptionUpdate,
  eventQuestionPush,
  eventStatusChange,
  etaUpdate,
}

class RealtimeEvent {
  final RealtimeEventType type;
  final Map<String, dynamic> payload;
  const RealtimeEvent(this.type, this.payload);
}

/// Manages the Socket.io connection and exposes streams for each event type.
class RealtimeService {
  io.Socket? _socket;

  final _controller = StreamController<RealtimeEvent>.broadcast();

  Stream<RealtimeEvent> get events => _controller.stream;

  Stream<Map<String, dynamic>> disruptions() => events
      .where((e) => e.type == RealtimeEventType.disruptionUpdate)
      .map((e) => e.payload);

  Stream<Map<String, dynamic>> eventQuestions() => events
      .where((e) => e.type == RealtimeEventType.eventQuestionPush)
      .map((e) => e.payload);

  Stream<Map<String, dynamic>> eventStatusChanges() => events
      .where((e) => e.type == RealtimeEventType.eventStatusChange)
      .map((e) => e.payload);

  Future<void> connect({String? authToken, BackendService? backendService}) async {
    if (_socket != null) return;

    var token = authToken;
    if (token == null) {
      try {
        final data = await (backendService ?? BackendService()).getRealtimeToken();
        token = data['token'] as String?;
      } catch (error) {
        debugPrint('[Realtime] token unavailable: $error');
        return;
      }
    }

    final wsUrl = ApiConfig.baseUrl;
    _socket = io.io(
      wsUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth({'token': token})
          .enableAutoConnect()
          .enableReconnection()
          .setReconnectionDelay(2000)
          .setReconnectionDelayMax(30000)
          .build(),
    );

    _socket!
      ..onConnect((_) => debugPrint('[Realtime] connected'))
      ..onDisconnect((_) => debugPrint('[Realtime] disconnected'))
      ..onError((e) => debugPrint('[Realtime] error: $e'))
      ..on('disruption:update', (data) {
        _push(
          RealtimeEventType.disruptionUpdate,
          _toMap(data),
        );
      })
      ..on('event:question', (data) {
        _push(
          RealtimeEventType.eventQuestionPush,
          _toMap(data),
        );
      })
      ..on('event:status', (data) {
        _push(
          RealtimeEventType.eventStatusChange,
          _toMap(data),
        );
      })
      ..on('eta:update', (data) {
        _push(
          RealtimeEventType.etaUpdate,
          _toMap(data),
        );
      });
  }

  void subscribeToLine(String lineId) {
    _socket?.emit('subscribe:line', {'lineId': lineId});
    debugPrint('[Realtime] subscribed to line:$lineId');
  }

  void subscribeToEvent(String eventId) {
    _socket?.emit('subscribe:event', {'eventId': eventId});
    debugPrint('[Realtime] subscribed to event:$eventId');
  }

  void unsubscribeFromEvent(String eventId) {
    _socket?.emit('unsubscribe:event', {'eventId': eventId});
  }

  void disconnect() {
    _socket?.dispose();
    _socket = null;
    debugPrint('[Realtime] disconnected by app');
  }

  void dispose() {
    disconnect();
    _controller.close();
  }

  void _push(RealtimeEventType type, Map<String, dynamic> payload) {
    if (!_controller.isClosed) {
      _controller.add(RealtimeEvent(type, payload));
    }
  }

  Map<String, dynamic> _toMap(dynamic data) {
    if (data is Map) return Map<String, dynamic>.from(data);
    return {};
  }
}

final realtimeServiceProvider = Provider<RealtimeService>((ref) {
  final service = RealtimeService();
  unawaited(service.connect());
  ref.onDispose(service.dispose);
  return service;
});

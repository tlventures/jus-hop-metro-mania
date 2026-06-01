import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'backend_service.dart';

/// Singleton that listens to network changes and auto-flushes the offline
/// outbox whenever the device regains connectivity.
class ConnectivityWatcher {
  ConnectivityWatcher._();
  static final ConnectivityWatcher instance = ConnectivityWatcher._();

  StreamSubscription<List<ConnectivityResult>>? _subscription;
  bool _online = true;

  void start(BackendService backend) {
    _subscription?.cancel();
    _subscription = Connectivity().onConnectivityChanged.listen(
      (results) => _onChanged(results, backend),
    );
  }

  void stop() {
    _subscription?.cancel();
    _subscription = null;
  }

  Future<void> _onChanged(
    List<ConnectivityResult> results,
    BackendService backend,
  ) async {
    final nowOnline = results.any((r) => r != ConnectivityResult.none);
    if (!_online && nowOnline) {
      debugPrint('[ConnectivityWatcher] back online — flushing outbox');
      try {
        await backend.flushOutbox();
        debugPrint('[ConnectivityWatcher] outbox flush complete');
      } catch (e) {
        debugPrint('[ConnectivityWatcher] flush error: $e');
      }
    }
    _online = nowOnline;
  }
}

/// Riverpod provider — keep alive for the app lifetime.
final connectivityWatcherProvider = Provider<ConnectivityWatcher>((ref) {
  final watcher = ConnectivityWatcher.instance;
  watcher.start(BackendService());
  ref.onDispose(watcher.stop);
  return watcher;
});

/// `StreamProvider<bool>` — true when online, false when offline.
final isOnlineProvider = StreamProvider<bool>((ref) {
  return Connectivity().onConnectivityChanged.map(
    (results) => results.any((r) => r != ConnectivityResult.none),
  );
});

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metrosafar/services/backend_service.dart';

class FeatureFlags {
  final Map<String, bool> values;

  const FeatureFlags(this.values);

  bool enabled(String key) => values[key] ?? false;

  bool get tripMode => enabled('phase5.trip_mode');
  bool get liveEtas => enabled('phase5.live_etas');
  bool get offlineCache => enabled('phase5.offline_cache');
  bool get stamps => enabled('phase6.stamps');
  bool get audioStories => enabled('phase6.audio_stories');
  bool get liveEvents => enabled('phase6.live_events');

  static const empty = FeatureFlags({});
}

final phase56BackendProvider = Provider((ref) => BackendService());

final featureFlagsProvider = FutureProvider<FeatureFlags>((ref) async {
  try {
    final data = await ref.watch(phase56BackendProvider).getFeatureFlags();
    final flags = Map<String, dynamic>.from(data['flags'] as Map? ?? {});
    return FeatureFlags(
      flags.map((key, value) => MapEntry(key, value == true)),
    );
  } catch (error) {
    debugPrint('featureFlagsProvider error: $error');
    return FeatureFlags.empty;
  }
});

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metrosafar/services/backend_service.dart';

final intelligenceBackendProvider = Provider((ref) => BackendService());

final liveEtasProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  try {
    return await ref.watch(intelligenceBackendProvider).getEtas(const [
      '1',
      '11',
    ]);
  } catch (error) {
    debugPrint('liveEtasProvider error: $error');
    return {'stations': const []};
  }
});

final disruptionsProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  try {
    return await ref.watch(intelligenceBackendProvider).getDisruptions();
  } catch (error) {
    debugPrint('disruptionsProvider error: $error');
    return {'disruptions': const []};
  }
});

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metrosafar/services/backend_service.dart';

final episodesProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  try {
    final data = await BackendService().getEpisodes();
    return (data['episodes'] as List<dynamic>? ?? [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  } catch (error) {
    debugPrint('episodesProvider error: $error');
    return const [];
  }
});

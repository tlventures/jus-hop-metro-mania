import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metrosafar/services/backend_service.dart';

final eventsScheduleProvider = FutureProvider<List<Map<String, dynamic>>>((
  ref,
) async {
  try {
    final data = await BackendService().getEventsSchedule();
    return (data['events'] as List<dynamic>? ?? [])
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  } catch (error) {
    debugPrint('eventsScheduleProvider error: $error');
    return const [];
  }
});

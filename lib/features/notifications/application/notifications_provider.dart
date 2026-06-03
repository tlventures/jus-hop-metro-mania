import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../services/backend_service.dart';

const _lastSeenKey = 'notif_last_seen_ms';

/// Number of feed notifications newer than the last time the user opened the
/// inbox. Drives the unread badge on the Home bell icon.
final unreadNotificationsProvider =
    FutureProvider.autoDispose<int>((ref) async {
  final data = await BackendService().getNotificationFeed();
  final raw = data['notifications'] as List<dynamic>? ?? [];
  final prefs = await SharedPreferences.getInstance();
  final lastSeenMs = prefs.getInt(_lastSeenKey) ?? 0;

  var unread = 0;
  for (final n in raw) {
    final created = (n as Map)['createdAt'] as String?;
    final ts = created != null ? DateTime.tryParse(created) : null;
    if (ts != null && ts.millisecondsSinceEpoch > lastSeenMs) unread++;
  }
  return unread;
});

/// Mark everything currently in the feed as read (called when the inbox opens)
/// and refresh the badge.
Future<void> markNotificationsRead(Ref ref) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setInt(_lastSeenKey, DateTime.now().millisecondsSinceEpoch);
  ref.invalidate(unreadNotificationsProvider);
}

/// WidgetRef variant for use from screens.
Future<void> markNotificationsReadW(WidgetRef ref) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setInt(_lastSeenKey, DateTime.now().millisecondsSinceEpoch);
  ref.invalidate(unreadNotificationsProvider);
}

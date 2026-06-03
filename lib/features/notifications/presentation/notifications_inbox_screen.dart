import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../design_system/tokens/radius.dart';
import '../../../design_system/tokens/spacing.dart';
import '../../../design_system/tokens/typography.dart';
import '../../../services/backend_service.dart';
import '../application/notifications_provider.dart';

class AppNotification {
  final String id;
  final String title;
  final String body;
  final DateTime? createdAt;

  const AppNotification({
    required this.id,
    required this.title,
    required this.body,
    this.createdAt,
  });

  factory AppNotification.fromJson(Map<String, dynamic> j) => AppNotification(
        id: j['id'] as String? ?? '',
        title: j['title'] as String? ?? 'MetroSafar',
        body: j['body'] as String? ?? '',
        createdAt: j['createdAt'] != null
            ? DateTime.tryParse(j['createdAt'] as String)
            : null,
      );
}

final notificationFeedProvider =
    FutureProvider.autoDispose<List<AppNotification>>((ref) async {
  final data = await BackendService().getNotificationFeed();
  final raw = data['notifications'] as List<dynamic>? ?? [];
  return raw
      .map((n) => AppNotification.fromJson(n as Map<String, dynamic>))
      .toList();
});

class NotificationsInboxScreen extends ConsumerStatefulWidget {
  const NotificationsInboxScreen({super.key});

  @override
  ConsumerState<NotificationsInboxScreen> createState() =>
      _NotificationsInboxScreenState();
}

class _NotificationsInboxScreenState
    extends ConsumerState<NotificationsInboxScreen> {
  @override
  void initState() {
    super.initState();
    // Opening the inbox marks everything as read → clears the bell badge.
    Future.microtask(() => markNotificationsReadW(ref));
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final async = ref.watch(notificationFeedProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Notifications')),
      body: RefreshIndicator(
        onRefresh: () async => ref.refresh(notificationFeedProvider.future),
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ListView(children: [
            const SizedBox(height: 160),
            const Center(child: Icon(Icons.error_outline, size: 44, color: Colors.redAccent)),
            const SizedBox(height: 12),
            Center(child: TextButton(
              onPressed: () => ref.invalidate(notificationFeedProvider),
              child: const Text('Couldn\'t load — retry'),
            )),
          ]),
          data: (items) {
            if (items.isEmpty) {
              return ListView(children: [
                const SizedBox(height: 140),
                Icon(Icons.notifications_none,
                    size: 64, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
                const SizedBox(height: AppSpacing.s4),
                Center(child: Text('No notifications yet',
                    style: AppTypography.titleMedium.copyWith(color: colorScheme.onSurface))),
                const SizedBox(height: AppSpacing.s2),
                Center(child: Text("We'll let you know about rewards, events and updates.",
                    textAlign: TextAlign.center,
                    style: AppTypography.bodySmall.copyWith(color: colorScheme.onSurfaceVariant))),
              ]);
            }
            return ListView.separated(
              padding: const EdgeInsets.all(AppSpacing.s4),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.s3),
              itemBuilder: (context, i) {
                final n = items[i];
                return Container(
                  padding: const EdgeInsets.all(AppSpacing.s4),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainer,
                    borderRadius: AppRadius.borderRadiusL,
                    border: Border.all(color: colorScheme.outline.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(AppSpacing.s2),
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer,
                          borderRadius: AppRadius.borderRadiusM,
                        ),
                        child: Icon(Icons.notifications,
                            size: 18, color: colorScheme.onPrimaryContainer),
                      ),
                      const SizedBox(width: AppSpacing.s3),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(n.title,
                                style: AppTypography.titleSmall.copyWith(
                                    color: colorScheme.onSurface, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 2),
                            Text(n.body,
                                style: AppTypography.bodySmall
                                    .copyWith(color: colorScheme.onSurfaceVariant)),
                            if (n.createdAt != null) ...[
                              const SizedBox(height: AppSpacing.s2),
                              Text(_relativeTime(n.createdAt!),
                                  style: AppTypography.labelSmall.copyWith(
                                      color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7))),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }

  String _relativeTime(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'Just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }
}

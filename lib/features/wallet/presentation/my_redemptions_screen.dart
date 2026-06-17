import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../design_system/tokens/colors.dart';
import '../../../design_system/tokens/radius.dart';
import '../../../design_system/tokens/spacing.dart';
import '../../../design_system/tokens/typography.dart';
import '../../../services/backend_service.dart';

// ---------------------------------------------------------------------------
// Model + provider
// ---------------------------------------------------------------------------

class RedemptionRecord {
  final String id;
  final String rewardTitle;
  final String category;
  final String discount;
  final int pointsCost;
  final String status; // pending | fulfilled | cancelled
  final String fulfillmentType; // manual | instant_code | affiliate_link
  final String? code; // present only when fulfilled
  final String? note;
  final DateTime? createdAt;

  const RedemptionRecord({
    required this.id,
    required this.rewardTitle,
    required this.category,
    required this.discount,
    required this.pointsCost,
    required this.status,
    required this.fulfillmentType,
    this.code,
    this.note,
    this.createdAt,
  });

  bool get isLink => fulfillmentType == 'affiliate_link';

  factory RedemptionRecord.fromJson(Map<String, dynamic> j) => RedemptionRecord(
        id: j['id'] as String? ?? '',
        rewardTitle: j['rewardTitle'] as String? ?? 'Reward',
        category: j['rewardCategory'] as String? ?? '',
        discount: j['discount'] as String? ?? '',
        pointsCost: (j['pointsCost'] as num?)?.toInt() ?? 0,
        status: j['status'] as String? ?? 'pending',
        fulfillmentType: j['fulfillmentType'] as String? ?? 'manual',
        code: j['fulfillmentCode'] as String?,
        note: j['fulfillmentNote'] as String?,
        createdAt: j['createdAt'] != null
            ? DateTime.tryParse(j['createdAt'] as String)
            : null,
      );
}

final myRedemptionsProvider =
    FutureProvider.autoDispose<List<RedemptionRecord>>((ref) async {
  final data = await BackendService().getMyRedemptions();
  final raw = data['redemptions'] as List<dynamic>? ?? [];
  return raw
      .map((r) => RedemptionRecord.fromJson(r as Map<String, dynamic>))
      .toList();
});

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class MyRedemptionsScreen extends ConsumerWidget {
  const MyRedemptionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final async = ref.watch(myRedemptionsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('My Redemptions')),
      body: RefreshIndicator(
        onRefresh: () async => ref.refresh(myRedemptionsProvider.future),
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => _ErrorState(onRetry: () => ref.invalidate(myRedemptionsProvider)),
          data: (items) {
            if (items.isEmpty) return const _EmptyState();
            return ListView.separated(
              padding: const EdgeInsets.all(AppSpacing.s6),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.s4),
              itemBuilder: (context, i) =>
                  _RedemptionCard(record: items[i], colorScheme: colorScheme),
            );
          },
        ),
      ),
    );
  }
}

class _RedemptionCard extends StatelessWidget {
  final RedemptionRecord record;
  final ColorScheme colorScheme;

  const _RedemptionCard({required this.record, required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.s5),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: AppRadius.borderRadiusXL,
        border: Border.all(color: colorScheme.outline.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  record.rewardTitle,
                  style: AppTypography.titleMedium
                      .copyWith(color: colorScheme.onSurface, fontWeight: FontWeight.w700),
                ),
              ),
              _StatusChip(status: record.status),
            ],
          ),
          if (record.discount.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.s1),
            Text(record.discount,
                style: AppTypography.bodySmall
                    .copyWith(color: colorScheme.onSurfaceVariant)),
          ],
          const SizedBox(height: AppSpacing.s2),
          Text('−${record.pointsCost} pts',
              style: AppTypography.labelMedium
                  .copyWith(color: AppColors.goldPoints, fontWeight: FontWeight.w700)),
          const SizedBox(height: AppSpacing.s4),
          _fulfillmentBody(context),
        ],
      ),
    );
  }

  Widget _fulfillmentBody(BuildContext context) {
    switch (record.status) {
      case 'fulfilled':
        if (record.code == null || record.code!.isEmpty) {
          return _infoLine(Icons.check_circle, 'Fulfilled', AppColors.electricTeal);
        }
        return record.isLink ? _LinkButton(url: record.code!) : _CodeBox(code: record.code!);
      case 'cancelled':
        return _infoLine(Icons.cancel_outlined, 'Cancelled — points refunded if applicable',
            colorScheme.error);
      default: // pending
        return _infoLine(Icons.hourglass_top,
            'Processing — your code will appear here shortly.', AppColors.warning);
    }
  }

  Widget _infoLine(IconData icon, String text, Color color) => Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: AppSpacing.s2),
          Expanded(
            child: Text(text,
                style: AppTypography.bodySmall.copyWith(color: color)),
          ),
        ],
      );
}

class _CodeBox extends StatelessWidget {
  final String code;
  const _CodeBox({required this.code});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s4, vertical: AppSpacing.s3),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: AppRadius.borderRadiusM,
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(code,
                style: AppTypography.titleMedium.copyWith(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                )),
          ),
          IconButton(
            icon: const Icon(Icons.copy, size: 18),
            tooltip: 'Copy code',
            onPressed: () {
              Clipboard.setData(ClipboardData(text: code));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Code copied to clipboard'),
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _LinkButton extends StatelessWidget {
  final String url;
  const _LinkButton({required this.url});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        icon: const Icon(Icons.open_in_new, size: 18),
        label: const Text('Open reward'),
        onPressed: () async {
          final uri = Uri.tryParse(url);
          if (uri != null && await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        },
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (status) {
      'fulfilled' => (AppColors.electricTeal, 'Ready'),
      'cancelled' => (Colors.grey, 'Cancelled'),
      _ => (AppColors.warning, 'Processing'),
    };
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s3, vertical: AppSpacing.s1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: AppRadius.borderRadiusFull,
      ),
      child: Text(label,
          style: AppTypography.labelSmall
              .copyWith(color: color, fontWeight: FontWeight.w700)),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return ListView(
      children: [
        const SizedBox(height: 120),
        Icon(Icons.card_giftcard_outlined,
            size: 64, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
        const SizedBox(height: AppSpacing.s4),
        Center(
          child: Text('No redemptions yet',
              style: AppTypography.titleMedium.copyWith(color: colorScheme.onSurface)),
        ),
        const SizedBox(height: AppSpacing.s2),
        Center(
          child: Text('Redeem your points for rewards in the Wallet.',
              style: AppTypography.bodySmall.copyWith(color: colorScheme.onSurfaceVariant)),
        ),
      ],
    );
  }
}

class _ErrorState extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        const SizedBox(height: 140),
        const Center(child: Icon(Icons.error_outline, size: 48, color: Colors.redAccent)),
        const SizedBox(height: AppSpacing.s3),
        Center(
          child: TextButton(onPressed: onRetry, child: const Text('Couldn\'t load — retry')),
        ),
      ],
    );
  }
}

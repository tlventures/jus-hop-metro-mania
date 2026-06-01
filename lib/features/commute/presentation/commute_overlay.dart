import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/city/current_city_provider.dart';
import '../../../core/commute/commute_provider.dart';
import '../../../core/commute/commute_session.dart';
import '../../../design_system/tokens/colors.dart';
import '../../../design_system/tokens/radius.dart';
import '../../../design_system/tokens/spacing.dart';
import '../../../design_system/tokens/typography.dart';
import 'commute_content_rail.dart';
import 'ticket_verification_sheet.dart';

class CommuteOverlay extends ConsumerWidget {
  const CommuteOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final commute = ref.watch(commuteProvider);
    if (!commute.isVisible) return const SizedBox.shrink();

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child:
          commute.phase == CommutePhase.confirmed
              ? _DetectedBanner(commute: commute)
              : _ActivePanel(commute: commute),
    );
  }
}

class _DetectedBanner extends ConsumerWidget {
  final CommuteSessionState commute;

  const _DetectedBanner({required this.commute});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cityId = ref.watch(activeCityProvider)?.id;
    final colorScheme = Theme.of(context).colorScheme;
    final station = commute.station?.name;

    return Container(
      key: const ValueKey('commute_detected'),
      margin: const EdgeInsets.only(bottom: AppSpacing.s4),
      padding: const EdgeInsets.all(AppSpacing.s4),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: AppRadius.borderRadiusXL,
      ),
      child: Row(
        children: [
          const Text('🚇', style: TextStyle(fontSize: 30)),
          const SizedBox(width: AppSpacing.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  station == null ? 'Commute detected' : 'Near $station',
                  style: AppTypography.labelLarge.copyWith(
                    color: colorScheme.onPrimaryContainer,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  'Tap to start earning with a 1.5x commute bonus.',
                  style: AppTypography.bodySmall.copyWith(
                    color: colorScheme.onPrimaryContainer.withValues(
                      alpha: 0.75,
                    ),
                  ),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () async {
              final verification = await showRideVerificationSheet(context);
              if (!context.mounted || verification == null) return;
              await ref
                  .read(commuteProvider.notifier)
                  .acceptDetected(
                    cityId: cityId,
                    ticketVerification: verification,
                  );
            },
            child: const Text('Start'),
          ),
        ],
      ),
    );
  }
}

class _ActivePanel extends ConsumerWidget {
  final CommuteSessionState commute;

  const _ActivePanel({required this.commute});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      key: const ValueKey('commute_active'),
      margin: const EdgeInsets.only(bottom: AppSpacing.s4),
      padding: const EdgeInsets.all(AppSpacing.s5),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.gradientStart, AppColors.gradientEnd],
        ),
        borderRadius: AppRadius.borderRadiusXL,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Commute Mode is live',
                  style: AppTypography.titleMedium.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.s3,
                  vertical: AppSpacing.s1,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: AppRadius.borderRadiusFull,
                ),
                child: Text(
                  '1.5x pts',
                  style: AppTypography.labelSmall.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s2),
          Text(
            'Tunnel-ready picks matched to your ride.',
            style: AppTypography.bodySmall.copyWith(color: Colors.white70),
          ),
          const SizedBox(height: AppSpacing.s4),
          const CommuteContentRail(estimatedMinutes: 15),
          const SizedBox(height: AppSpacing.s4),
          Row(
            children: [
              Expanded(
                child: FilledButton(
                  onPressed: () => context.go('/play'),
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppColors.gradientStart,
                  ),
                  child: const Text('Play now'),
                ),
              ),
              const SizedBox(width: AppSpacing.s3),
              OutlinedButton(
                onPressed: () => ref.read(commuteProvider.notifier).end(),
                style: OutlinedButton.styleFrom(foregroundColor: Colors.white),
                child: const Text('End'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

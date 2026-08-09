import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metrosafar/design_system/tokens/colors.dart';
import 'package:metrosafar/design_system/tokens/radius.dart';
import 'package:metrosafar/design_system/tokens/spacing.dart';
import 'package:metrosafar/design_system/tokens/typography.dart';
import 'package:metrosafar/features/intelligence/application/intelligence_provider.dart';

class DisruptionBanner extends ConsumerWidget {
  const DisruptionBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final disruptions =
        ref.watch(disruptionsProvider).valueOrNull?['disruptions']
            as List<dynamic>? ??
        [];
    if (disruptions.isEmpty) return const SizedBox.shrink();

    final first = Map<String, dynamic>.from(disruptions.first as Map);
    return Container(
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.s6,
        AppSpacing.s4,
        AppSpacing.s6,
        0,
      ),
      padding: const EdgeInsets.all(AppSpacing.s3),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.14),
        borderRadius: AppRadius.borderRadiusL,
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: AppColors.warning),
          const SizedBox(width: AppSpacing.s2),
          Expanded(
            child: Text(
              first['title'] as String? ?? 'Metro service update',
              style: AppTypography.bodySmall,
            ),
          ),
        ],
      ),
    );
  }
}

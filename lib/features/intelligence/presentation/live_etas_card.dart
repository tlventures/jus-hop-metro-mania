import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:metrosafar/design_system/tokens/colors.dart';
import 'package:metrosafar/design_system/tokens/radius.dart';
import 'package:metrosafar/design_system/tokens/spacing.dart';
import 'package:metrosafar/design_system/tokens/typography.dart';
import 'package:metrosafar/features/intelligence/application/intelligence_provider.dart';

class LiveEtasCard extends ConsumerWidget {
  const LiveEtasCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final etas = ref.watch(liveEtasProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return etas.when(
      data: (data) {
        final stations = (data['stations'] as List<dynamic>? ?? []);
        return Container(
          padding: const EdgeInsets.all(AppSpacing.s4),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainer,
            borderRadius: AppRadius.borderRadiusXL,
            border: Border.all(color: colorScheme.outline.withValues(alpha: 0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(
                    Icons.train_outlined,
                    color: AppColors.metroIndigo,
                  ),
                  const SizedBox(width: AppSpacing.s2),
                  Expanded(
                    child: Text(
                      'Live metro intelligence',
                      style: AppTypography.titleMedium.copyWith(
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => context.go('/journey-planner'),
                    child: const Text('Plan'),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.s3),
              if (stations.isEmpty)
                Text(
                  'Expected timetable data will appear here when enabled.',
                  style: AppTypography.bodySmall.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                )
              else
                ...stations.take(2).map((station) {
                  final map = Map<String, dynamic>.from(station as Map);
                  final arrivals = (map['arrivals'] as List<dynamic>? ?? []);
                  final first =
                      arrivals.isEmpty
                          ? null
                          : Map<String, dynamic>.from(arrivals.first as Map);
                  final etaMinutes =
                      ((first?['etaSeconds'] as num? ?? 0) / 60).ceil();
                  return Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.s2),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            map['stationName'] as String? ?? 'Metro station',
                            style: AppTypography.bodyMedium.copyWith(
                              color: colorScheme.onSurface,
                            ),
                          ),
                        ),
                        Text(
                          etaMinutes <= 0 ? 'Now' : '${etaMinutes}m',
                          style: AppTypography.labelLarge.copyWith(
                            color: AppColors.mintSuccess,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  );
                }),
            ],
          ),
        );
      },
      loading: () => const LinearProgressIndicator(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

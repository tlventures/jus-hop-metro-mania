import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metrosafar/core/city/current_city_provider.dart';
import 'package:metrosafar/design_system/tokens/colors.dart';
import 'package:metrosafar/design_system/tokens/radius.dart';
import 'package:metrosafar/design_system/tokens/spacing.dart';
import 'package:metrosafar/design_system/tokens/typography.dart';
import 'package:metrosafar/features/stamps/application/stamps_provider.dart';
import 'package:metrosafar/services/localization_service.dart';

class StampsScreen extends ConsumerStatefulWidget {
  const StampsScreen({super.key});

  @override
  ConsumerState<StampsScreen> createState() => _StampsScreenState();
}

class _StampsScreenState extends ConsumerState<StampsScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(stampsProvider.notifier).load());
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(stampsProvider);
    final notifier = ref.read(stampsProvider.notifier);
    final colorScheme = Theme.of(context).colorScheme;
    final owned =
        state.stamps
            .where((stamp) => (stamp['ownedCount'] as num? ?? 0) > 0)
            .length;

    // City-aware header copy.
    final city     = ref.watch(activeCityProvider);
    final locale   = ref.watch(localeProvider).languageCode;
    final cityName = city?.displayName(locale) ?? 'your city';
    final operator = city?.operatorShortName ?? 'Metro';

    return Scaffold(
      appBar: AppBar(title: const Text('Station Stamps')),
      body: RefreshIndicator(
        onRefresh: notifier.load,
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.s6),
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.s6),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.goldPoints, AppColors.warmCoral],
                ),
                borderRadius: AppRadius.borderRadiusXXL,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$owned / ${state.stamps.length}',
                    style: AppTypography.displaySmall.copyWith(
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s2),
                  Text(
                    'Collect $operator station stamps as you explore $cityName.',
                    style: AppTypography.bodyMedium.copyWith(
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
            ),
            if (state.message != null) ...[
              const SizedBox(height: AppSpacing.s4),
              Text(state.message!, style: AppTypography.bodySmall),
            ],
            const SizedBox(height: AppSpacing.s6),
            Text(
              'Collections',
              style: AppTypography.titleMedium.copyWith(
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: AppSpacing.s3),
            ...state.collections.take(3).map((collection) {
              final total = (collection['total'] as num?)?.toInt() ?? 1;
              final progress = (collection['progress'] as num?)?.toInt() ?? 0;
              return Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.s3),
                child: LinearProgressIndicator(
                  value: total == 0 ? 0 : progress / total,
                  minHeight: 8,
                  borderRadius: const BorderRadius.all(Radius.circular(99)),
                ),
              );
            }),
            const SizedBox(height: AppSpacing.s6),
            if (state.isLoading) const LinearProgressIndicator(),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: state.stamps.length,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: AppSpacing.s4,
                mainAxisSpacing: AppSpacing.s4,
                childAspectRatio: 0.9,
              ),
              itemBuilder: (context, index) {
                final stamp = state.stamps[index];
                return _StampCard(
                  stamp: stamp,
                  onClaim: () => notifier.claim(stamp['stationId'] as String),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _StampCard extends StatelessWidget {
  final Map<String, dynamic> stamp;
  final VoidCallback onClaim;

  const _StampCard({required this.stamp, required this.onClaim});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final ownedCount = (stamp['ownedCount'] as num?)?.toInt() ?? 0;
    final rarity = stamp['rarity'] as String? ?? 'common';
    final color = switch (rarity) {
      'epic' => AppColors.warmCoral,
      'rare' => AppColors.metroIndigo,
      _ => AppColors.mintSuccess,
    };

    return InkWell(
      borderRadius: AppRadius.borderRadiusXL,
      onTap: onClaim,
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.s4),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainer,
          borderRadius: AppRadius.borderRadiusXL,
          border: Border.all(
            color: color.withValues(alpha: ownedCount > 0 ? 0.9 : 0.25),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              backgroundColor: color.withValues(alpha: 0.14),
              child: Icon(Icons.confirmation_number_outlined, color: color),
            ),
            const Spacer(),
            Text(
              stamp['stationName'] as String? ??
                  stamp['name'] as String? ??
                  'Station',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.titleSmall.copyWith(
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: AppSpacing.s1),
            Text(
              ownedCount > 0 ? 'Owned x$ownedCount' : rarity,
              style: AppTypography.labelSmall.copyWith(
                color: ownedCount > 0 ? color : colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import '../../../../design_system/components/brand_logo.dart';
import '../../../../design_system/tokens/colors.dart';

import '../../../../design_system/tokens/spacing.dart';
import '../../../../design_system/tokens/typography.dart';

class WelcomeScreen extends StatelessWidget {
  final VoidCallback onNext;
  final VoidCallback onSkip;

  const WelcomeScreen({required this.onNext, required this.onSkip, super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      // Branded background so no white band ever shows behind system bars.
      backgroundColor: AppColors.cityInk,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.cityInk,
              AppColors.electricTeal.withValues(alpha: 0.92),
              AppColors.signalPink.withValues(alpha: 0.9),
            ],
            stops: const [0.0, 0.54, 1.0],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Responsive sizing — scales from small phones to tablets.
              final width = constraints.maxWidth;
              final headlineSize = (width * 0.11).clamp(32.0, 56.0).toDouble();
              final isWide = width > 600;

              // Overflow-proof layout: no IntrinsicHeight/Spacer (their
              // intrinsic-height math can disagree with real layout and clip
              // on short screens). The column is forced to at least the
              // viewport height and spaceBetween distributes any extra space
              // between the header, hero, and buttons; when content is taller
              // than the screen it simply scrolls.
              return SingleChildScrollView(
                child: Center(
                  child: ConstrainedBox(
                    // Cap content width on tablets / foldables / notepads.
                    constraints: BoxConstraints(
                      maxWidth: 560,
                      minHeight: constraints.maxHeight,
                    ),
                    child: Padding(
                      padding: EdgeInsets.all(
                        isWide ? AppSpacing.s8 : AppSpacing.s6,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              const MetroSafarLogo(size: 48, elevated: false),
                              const SizedBox(width: AppSpacing.s3),
                              Expanded(
                                child: Text(
                                  'MetroSafar',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTypography.titleLarge.copyWith(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                              TextButton(
                                onPressed: onSkip,
                                child: Text(
                                  'Skip',
                                  style: AppTypography.labelLarge.copyWith(
                                    color: Colors.white.withValues(alpha: 0.86),
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: AppSpacing.s8),
                              const _SignalPill(
                                icon: Icons.bolt_outlined,
                                label: 'Rewards go live before ticketing',
                              ),
                              const SizedBox(height: AppSpacing.s5),
                              Text(
                                'Ride. Earn. Own your city.',
                                style: AppTypography.displayLarge.copyWith(
                                  color: Colors.white,
                                  fontSize: headlineSize,
                                  fontWeight: FontWeight.w900,
                                  height: 1.02,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.s4),
                              Text(
                                'Turn everyday metro trips into points, streaks, city drops, and rewards built for your commute.',
                                style: AppTypography.bodyLarge.copyWith(
                                  color: Colors.white.withValues(alpha: 0.82),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.s6),
                              const Row(
                                children: [
                                  Expanded(
                                    child: _PreviewStat(
                                      icon: Icons.local_fire_department_outlined,
                                      label: 'Streaks',
                                      value: 'Daily',
                                    ),
                                  ),
                                  SizedBox(width: AppSpacing.s3),
                                  Expanded(
                                    child: _PreviewStat(
                                      icon: Icons.card_giftcard_outlined,
                                      label: 'Rewards',
                                      value: 'Points',
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: AppSpacing.s3),
                              const Row(
                                children: [
                                  Expanded(
                                    child: _PreviewStat(
                                      icon: Icons.map_outlined,
                                      label: 'City',
                                      value: 'Local',
                                    ),
                                  ),
                                  SizedBox(width: AppSpacing.s3),
                                  Expanded(
                                    child: _PreviewStat(
                                      icon: Icons.sports_esports_outlined,
                                      label: 'Play',
                                      value: 'Earn',
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const SizedBox(height: AppSpacing.s8),
                              FilledButton.icon(
                                onPressed: onNext,
                                icon: const Icon(Icons.arrow_forward),
                                label: const Text('Start earning'),
                                style: FilledButton.styleFrom(
                                  backgroundColor: AppColors.neonLime,
                                  foregroundColor: AppColors.cityInk,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.s3),
                              OutlinedButton.icon(
                                onPressed: onSkip,
                                icon: const Icon(Icons.explore_outlined),
                                label: const Text('Explore first'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Colors.white,
                                  side: BorderSide(
                                    color: Colors.white.withValues(alpha: 0.55),
                                  ),
                                  backgroundColor: colorScheme.surface
                                      .withValues(alpha: 0.08),
                                ),
                              ),
                              const SizedBox(height: AppSpacing.s2),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _SignalPill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _SignalPill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s3,
        vertical: AppSpacing.s2,
      ),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: AppColors.neonLime, size: 16),
          const SizedBox(width: AppSpacing.s2),
          Flexible(
            child: Text(
              label,
              style: AppTypography.labelSmall.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewStat extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _PreviewStat({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 82),
      padding: const EdgeInsets.all(AppSpacing.s3),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icon, color: AppColors.neonLime, size: 22),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.titleMedium.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTypography.labelSmall.copyWith(
                  color: Colors.white.withValues(alpha: 0.72),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
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
      body: Container(
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
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.s6),
            child: Stack(
              children: [
                Positioned(
                  right: -60,
                  top: 24,
                  child: Icon(
                    Icons.radio_button_checked,
                    size: 220,
                    color: Colors.white.withValues(alpha: 0.06),
                  ),
                ),
                Positioned(
                  left: -38,
                  bottom: 130,
                  child: Icon(
                    Icons.route_outlined,
                    size: 180,
                    color: AppColors.neonLime.withValues(alpha: 0.12),
                  ),
                ),
                SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 48,
                            height: 48,
                            decoration: BoxDecoration(
                              color: AppColors.neonLime,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: const Icon(
                              Icons.train_outlined,
                              color: AppColors.cityInk,
                            ),
                          ),
                          const SizedBox(width: AppSpacing.s3),
                          Text(
                            'MetroSafar',
                            style: AppTypography.titleLarge.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const Spacer(),
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
                      const SizedBox(height: AppSpacing.s12),
                      _SignalPill(
                        icon: Icons.bolt_outlined,
                        label: 'Rewards go live before ticketing',
                      ),
                      const SizedBox(height: AppSpacing.s5),
                      Text(
                        'Ride. Earn. Own your city.',
                        style: AppTypography.displayLarge.copyWith(
                          color: Colors.white,
                          fontSize: 44,
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
                          backgroundColor: colorScheme.surface.withValues(
                            alpha: 0.08,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
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

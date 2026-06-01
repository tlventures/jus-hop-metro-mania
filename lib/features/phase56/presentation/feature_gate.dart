import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../design_system/tokens/spacing.dart';
import '../../../design_system/tokens/typography.dart';
import '../application/feature_flags_provider.dart';

typedef FeatureFlagSelector = bool Function(FeatureFlags flags);

class FeatureGate extends ConsumerWidget {
  final FeatureFlagSelector enabled;
  final String featureName;
  final Widget child;

  const FeatureGate({
    super.key,
    required this.enabled,
    required this.featureName,
    required this.child,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flags = ref.watch(featureFlagsProvider);

    return flags.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) => _UnavailableFeatureScreen(featureName: featureName),
      data: (value) => enabled(value)
          ? child
          : _UnavailableFeatureScreen(featureName: featureName),
    );
  }
}

class _UnavailableFeatureScreen extends StatelessWidget {
  final String featureName;

  const _UnavailableFeatureScreen({required this.featureName});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(featureName),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.s6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.lock_clock_outlined,
                size: 52,
                color: colorScheme.primary,
              ),
              const SizedBox(height: AppSpacing.s4),
              Text(
                '$featureName is coming soon',
                textAlign: TextAlign.center,
                style: AppTypography.headlineSmall.copyWith(
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: AppSpacing.s2),
              Text(
                'We are polishing this feature before opening it up.',
                textAlign: TextAlign.center,
                style: AppTypography.bodyMedium.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.s5),
              FilledButton(
                onPressed: () => context.go('/home'),
                child: const Text('Back to Home'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

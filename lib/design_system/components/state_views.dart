import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../tokens/spacing.dart';
import '../tokens/typography.dart';

/// Branded full-screen states shared across feature screens so error, empty,
/// and loading views look consistent instead of bare spinners / "Error" text.

/// Error state: tinted icon + title + message + retry button.
class AppErrorState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final VoidCallback? onRetry;
  final String retryLabel;

  const AppErrorState({
    super.key,
    this.icon = Icons.cloud_off,
    this.title = "Something went wrong",
    this.message = "Please check your connection and try again.",
    this.onRetry,
    this.retryLabel = 'Try again',
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _IconBadge(icon: icon, color: scheme.error, bg: scheme.errorContainer),
            const SizedBox(height: AppSpacing.s5),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTypography.titleMedium
                  .copyWith(color: scheme.onSurface, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AppSpacing.s2),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium
                  .copyWith(color: scheme.onSurfaceVariant),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: AppSpacing.s6),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: Text(retryLabel),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Empty state: tinted icon + title + message + optional action.
class AppEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  const AppEmptyState({
    super.key,
    this.icon = Icons.inbox_outlined,
    required this.title,
    required this.message,
    this.action,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _IconBadge(
              icon: icon,
              color: scheme.primary,
              bg: scheme.primaryContainer,
            ),
            const SizedBox(height: AppSpacing.s5),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTypography.titleMedium
                  .copyWith(color: scheme.onSurface, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: AppSpacing.s2),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium
                  .copyWith(color: scheme.onSurfaceVariant),
            ),
            if (action != null) ...[
              const SizedBox(height: AppSpacing.s6),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

class _IconBadge extends StatelessWidget {
  final IconData icon;
  final Color color;
  final Color bg;
  const _IconBadge({required this.icon, required this.color, required this.bg});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
      child: Icon(icon, size: 34, color: color),
    );
  }
}

/// Shimmer skeleton placeholder. Use [AppLoadingSkeleton.list] for a generic
/// stacked-card list, or [AppLoadingSkeleton.home] for the home layout.
class AppLoadingSkeleton extends StatelessWidget {
  final List<Widget> blocks;
  const AppLoadingSkeleton._(this.blocks);

  factory AppLoadingSkeleton.list({int rows = 5}) {
    return AppLoadingSkeleton._([
      for (var i = 0; i < rows; i++) ...[
        const _SkelBlock(height: 72),
        const SizedBox(height: AppSpacing.s4),
      ],
    ]);
  }

  /// Mimics the home screen: a hero card, a strip, then a couple of sections.
  factory AppLoadingSkeleton.home() {
    return const AppLoadingSkeleton._([
      _SkelBlock(height: 132, radius: 20),
      SizedBox(height: AppSpacing.s4),
      _SkelBlock(height: 72, radius: 16),
      SizedBox(height: AppSpacing.s5),
      _SkelBlock(height: 20, width: 140, radius: 6),
      SizedBox(height: AppSpacing.s3),
      _SkelBlock(height: 120, radius: 16),
      SizedBox(height: AppSpacing.s5),
      _SkelBlock(height: 20, width: 160, radius: 6),
      SizedBox(height: AppSpacing.s3),
      _SkelBlock(height: 96, radius: 16),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Shimmer.fromColors(
      baseColor: scheme.surfaceContainerHighest,
      highlightColor: scheme.surfaceContainer,
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.s4),
        children: blocks,
      ),
    );
  }
}

class _SkelBlock extends StatelessWidget {
  final double height;
  final double? width;
  final double radius;
  const _SkelBlock({required this.height, this.width, this.radius = 12});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: height,
      width: width ?? double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import '../tokens/colors.dart';
import '../tokens/radius.dart';
import '../tokens/spacing.dart';
import '../tokens/typography.dart';

/// Custom scaffold with gradient AppBar and polish
class AppScaffold extends StatelessWidget {
  final String? title;
  final Widget? leading;
  final List<Widget>? actions;
  final Widget body;
  final Widget? bottomNavigationBar;
  final Widget? floatingActionButton;
  final FloatingActionButtonLocation? floatingActionButtonLocation;
  final bool hasGradientHeader;
  final VoidCallback? onBackPressed;

  const AppScaffold({
    required this.body,
    this.title,
    this.leading,
    this.actions,
    this.bottomNavigationBar,
    this.floatingActionButton,
    this.floatingActionButtonLocation,
    this.hasGradientHeader = true,
    this.onBackPressed,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: title != null
            ? Text(
                title!,
                style: AppTypography.headlineMedium.copyWith(
                  color: colorScheme.onSurface,
                ),
              )
            : null,
        leading: leading ??
            (Navigator.of(context).canPop()
                ? IconButton(
                    icon: Icon(Icons.arrow_back, color: colorScheme.onSurface),
                    tooltip: 'Back',
                    onPressed: onBackPressed ?? () => Navigator.pop(context),
                  )
                : null),
        actions: actions,
        backgroundColor: colorScheme.surface,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      body: body,
      bottomNavigationBar: bottomNavigationBar,
      floatingActionButton: floatingActionButton,
      floatingActionButtonLocation: floatingActionButtonLocation,
    );
  }
}

/// Glass morphism card for hero surfaces
class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets? padding;
  final double? width;
  final double? height;
  final VoidCallback? onTap;

  const GlassCard({
    required this.child,
    this.padding,
    this.width,
    this.height,
    this.onTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: width,
        height: height,
        padding: padding ?? const EdgeInsets.all(AppSpacing.s6),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppColors.gradientStart.withValues(alpha: 0.1),
              AppColors.gradientEnd.withValues(alpha: 0.05),
            ],
          ),
          borderRadius: AppRadius.borderRadiusXL,
          border: Border.all(
            color: colorScheme.outline.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
        child: child,
      ),
    );
  }
}

/// Shimmer loading skeleton
class ShimmerBox extends StatelessWidget {
  final double? width;
  final double? height;
  final BorderRadius? borderRadius;

  const ShimmerBox({
    this.width,
    this.height = 16,
    this.borderRadius,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: borderRadius ?? AppRadius.borderRadiusS,
      ),
      child: ShaderMask(
        shaderCallback: (bounds) {
          return LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: [
              colorScheme.surfaceContainerHighest,
              colorScheme.surface,
              colorScheme.surfaceContainerHighest,
            ],
            stops: const [0.0, 0.5, 1.0],
          ).createShader(bounds);
        },
        child: Container(
          color: colorScheme.surface,
        ),
      ),
    );
  }
}

/// Empty state with icon, title, and CTA
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? ctaLabel;
  final VoidCallback? onCtaTapped;

  const EmptyState({
    required this.icon,
    required this.title,
    this.subtitle,
    this.ctaLabel,
    this.onCtaTapped,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            icon,
            size: 80,
            color: colorScheme.primary.withValues(alpha: 0.3),
          ),
          const SizedBox(height: AppSpacing.s6),
          Text(
            title,
            style: AppTypography.headlineMedium.copyWith(color: colorScheme.onSurface),
            textAlign: TextAlign.center,
          ),
          if (subtitle != null) ...[
            const SizedBox(height: AppSpacing.s3),
            Text(
              subtitle!,
              style: AppTypography.bodyMedium.copyWith(color: colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
          if (ctaLabel != null) ...[
            const SizedBox(height: AppSpacing.s8),
            FilledButton(
              onPressed: onCtaTapped ?? () {},
              child: Text(ctaLabel!),
            ),
          ],
        ],
      ),
    );
  }
}

/// Error state with retry
class ErrorState extends StatelessWidget {
  final String message;
  final String? retryLabel;
  final VoidCallback? onRetry;

  const ErrorState({
    required this.message,
    this.retryLabel = 'Retry',
    this.onRetry,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s6),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 80,
              color: colorScheme.error.withValues(alpha: 0.3),
            ),
            const SizedBox(height: AppSpacing.s6),
            Text(
              'Oops, something went wrong',
              style: AppTypography.headlineMedium.copyWith(color: colorScheme.onSurface),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.s3),
            Text(
              message,
              style: AppTypography.bodyMedium.copyWith(color: colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.s8),
            if (onRetry != null)
              FilledButton(
                onPressed: onRetry,
                child: Text(retryLabel ?? 'Retry'),
              ),
          ],
        ),
      ),
    );
  }
}

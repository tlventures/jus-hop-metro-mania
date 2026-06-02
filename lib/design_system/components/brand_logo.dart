import 'package:flutter/material.dart';
import '../tokens/colors.dart';

/// The canonical MetroSafar brand mark — matches the launcher icon.
///
/// Use this everywhere a logo appears (splash, onboarding, login) so the
/// brand stays consistent across the whole app. Falls back to a branded
/// train glyph if the asset fails to load.
class MetroSafarLogo extends StatelessWidget {
  /// Edge length of the (square) logo in logical pixels.
  final double size;

  /// Corner radius. Defaults to ~22% of [size] to mirror the adaptive icon.
  final double? borderRadius;

  /// Whether to cast a soft shadow beneath the logo.
  final bool elevated;

  const MetroSafarLogo({
    super.key,
    this.size = 80,
    this.borderRadius,
    this.elevated = true,
  });

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? size * 0.22;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        boxShadow: elevated
            ? [
                BoxShadow(
                  color: AppColors.cityInk.withValues(alpha: 0.18),
                  blurRadius: size * 0.18,
                  offset: Offset(0, size * 0.06),
                ),
              ]
            : null,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Image.asset(
          'assets/brand/metrosafar_icon_1024.png',
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stack) => _Fallback(size: size, radius: radius),
        ),
      ),
    );
  }
}

class _Fallback extends StatelessWidget {
  final double size;
  final double radius;

  const _Fallback({required this.size, required this.radius});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.gradientStart, AppColors.gradientEnd],
        ),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Icon(Icons.train, color: Colors.white, size: size * 0.5),
    );
  }
}

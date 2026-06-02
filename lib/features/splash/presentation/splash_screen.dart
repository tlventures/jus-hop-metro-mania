import 'package:flutter/material.dart';
import '../../../design_system/components/brand_logo.dart';
import '../../../design_system/tokens/colors.dart';
import '../../../design_system/tokens/typography.dart';

/// Branded launch screen shown while the app boots (Firebase, services,
/// audio, router). Displays an animated rotating ring around the brand logo
/// so users on slower/older devices see clear "launching" feedback instead
/// of a frozen white screen.
class SplashScreen extends StatefulWidget {
  /// When non-null, shows an error state with a retry button.
  final Object? error;
  final VoidCallback? onRetry;

  const SplashScreen({super.key, this.error, this.onRetry});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _spin;
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _spin = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _spin.dispose();
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    // Logo scales gently with screen size (phones → tablets), clamped.
    final logoSize = (size.shortestSide * 0.26).clamp(96.0, 200.0);
    final ringSize = logoSize * 1.5;
    final hasError = widget.error != null;

    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.cityInk,
              Color(0xFF0C3B3A),
              AppColors.electricTeal,
            ],
            stops: [0.0, 0.55, 1.0],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Spacer(flex: 3),
                // Logo with animated rotating ring
                SizedBox(
                  width: ringSize,
                  height: ringSize,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      if (!hasError)
                        RotationTransition(
                          turns: _spin,
                          child: CustomPaint(
                            size: Size(ringSize, ringSize),
                            painter: _RingPainter(),
                          ),
                        ),
                      ScaleTransition(
                        scale: Tween<double>(begin: 0.96, end: 1.04).animate(
                          CurvedAnimation(parent: _pulse, curve: Curves.easeInOut),
                        ),
                        child: MetroSafarLogo(size: logoSize),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 28),
                Text(
                  'MetroSafar',
                  style: AppTypography.headlineMedium.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  hasError ? 'Something went wrong' : 'Getting your city ready…',
                  style: AppTypography.bodyMedium.copyWith(
                    color: Colors.white.withValues(alpha: 0.78),
                  ),
                ),
                const Spacer(flex: 2),
                if (hasError && widget.onRetry != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: FilledButton.icon(
                      onPressed: widget.onRetry,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Retry'),
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.neonLime,
                        foregroundColor: AppColors.cityInk,
                      ),
                    ),
                  )
                else
                  const Padding(
                    padding: EdgeInsets.only(bottom: 40),
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        valueColor: AlwaysStoppedAnimation(AppColors.neonLime),
                      ),
                    ),
                  ),
                const Spacer(flex: 1),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Draws a partial arc ring (gradient sweep) that rotates to indicate loading.
class _RingPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4;

    // Faint full track
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..color = Colors.white.withValues(alpha: 0.12);
    canvas.drawCircle(center, radius, track);

    // Bright sweeping arc
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..shader = const SweepGradient(
        colors: [Colors.transparent, AppColors.neonLime],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      0,
      3.6, // ~206° sweep
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

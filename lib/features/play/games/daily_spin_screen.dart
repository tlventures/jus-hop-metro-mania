import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math';
import '../../../design_system/components/game_shell.dart';
import '../../../design_system/tokens/colors.dart';
import '../../../design_system/tokens/radius.dart';
import '../../../design_system/tokens/spacing.dart';
import '../../../design_system/tokens/typography.dart';
import '../application/games_provider.dart';

class DailySpinScreen extends ConsumerStatefulWidget {
  const DailySpinScreen({super.key});

  @override
  ConsumerState<DailySpinScreen> createState() => _DailySpinScreenState();
}

class _DailySpinScreenState extends ConsumerState<DailySpinScreen>
    with TickerProviderStateMixin {
  late AnimationController _wheelController;
  late AnimationController _confettiController;

  final List<SpinSegment> segments = [
    SpinSegment('50 pts', '+50', AppColors.goldPoints),
    SpinSegment('100 pts', '+100', const Color(0xFF8B5CF6)),
    SpinSegment('10 pts', '+10', const Color(0xFF06B6D4)),
    SpinSegment('🎁 Mystery', 'Special', const Color(0xFFF97316)),
    SpinSegment('75 pts', '+75', const Color(0xFF10B981)),
    SpinSegment('200 pts', '+200', const Color(0xFFEC4899)),
    SpinSegment('25 pts', '+25', const Color(0xFFFCD34D)),
    SpinSegment('🎊 Lucky!', '+150', const Color(0xFFEF4444)),
  ];

  bool isSpinning = false;
  int selectedSegmentIndex = 0;
  bool showReward = false;
  SpinSegment? rewardSegment;
  int pointsEarned = 0;
  bool hasSpunToday = false;

  static const _lastSpinDateKey = 'daily_spin_last_spin_date';
  static const _lastSpinPointsKey = 'daily_spin_last_spin_points';
  static const _lastSpinLabelKey = 'daily_spin_last_spin_label';

  @override
  void initState() {
    super.initState();
    _wheelController = AnimationController(
      duration: const Duration(seconds: 5),
      vsync: this,
    );
    _confettiController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    );
    _loadSpinState();
  }

  @override
  void dispose() {
    _wheelController.dispose();
    _confettiController.dispose();
    super.dispose();
  }

  Future<void> _loadSpinState() async {
    final prefs = await SharedPreferences.getInstance();
    final lastSpinDate = prefs.getString(_lastSpinDateKey);
    if (!mounted || lastSpinDate != _todayKey()) return;

    final lastLabel = prefs.getString(_lastSpinLabelKey);
    final segment = segments.firstWhere(
      (item) => item.label == lastLabel,
      orElse: () => segments.first,
    );

    setState(() {
      hasSpunToday = true;
      showReward = true;
      rewardSegment = segment;
      pointsEarned = prefs.getInt(_lastSpinPointsKey) ?? _pointsFor(segment);
    });
  }

  String _todayKey() => DateTime.now().toIso8601String().substring(0, 10);

  int _pointsFor(SpinSegment segment) {
    final digits = segment.reward.replaceAll(RegExp(r'[^\d]'), '');
    return int.tryParse(digits) ?? 75;
  }

  Future<void> _saveSpinState(SpinSegment segment, int points) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastSpinDateKey, _todayKey());
    await prefs.setString(_lastSpinLabelKey, segment.label);
    await prefs.setInt(_lastSpinPointsKey, points);
  }

  void _spin() {
    if (isSpinning || hasSpunToday) {
      _showAlreadySpunMessage();
      return;
    }

    HapticFeedback.heavyImpact();

    setState(() {
      isSpinning = true;
      showReward = false;
    });

    // Random segment (0-7)
    final randomSegment = Random().nextInt(segments.length);

    _wheelController.forward(from: 0.0).then((_) async {
      final segment = segments[randomSegment];
      final points = _pointsFor(segment);
      await _saveSpinState(segment, points);
      if (!mounted) return;

      setState(() {
        selectedSegmentIndex = randomSegment;
        rewardSegment = segment;
        pointsEarned = points;
        showReward = true;
        isSpinning = false;
        hasSpunToday = true;
      });

      HapticFeedback.heavyImpact();
      _confettiController.forward();

      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          _showRewardBottomSheet();
        }
      });
    });
  }

  void _showRewardBottomSheet() {
    ref.read(gamesProvider.notifier).updateGameScore('daily_spin', pointsEarned);

    showModalBottomSheet(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.borderRadiusXXL,
      ),
      builder: (context) => GameEndBottomSheet(
        title: 'Congratulations! 🎉',
        score: pointsEarned,
        points: pointsEarned,
        message: 'Claim your reward and comeback tomorrow for another spin!',
        icon: Center(
          child: Text(
            rewardSegment?.label ?? '🎁',
            style: const TextStyle(fontSize: 80),
          ),
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () {
                Navigator.pop(context);
                _resetSpin();
              },
              child: const Text('Claim & Continue'),
            ),
          ),
          const SizedBox(height: AppSpacing.s3),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _shareReward,
              child: const Text('Share'),
            ),
          ),
        ],
      ),
    );
  }

  void _resetSpin() {
    setState(() {
      _wheelController.reset();
      _confettiController.reset();
    });
  }

  Future<void> _shareReward() async {
    final points = pointsEarned;
    final label = rewardSegment?.label ?? '$points pts';
    await SharePlus.instance.share(
      ShareParams(
        text:
            'I just won $label on MetroSafar Daily Spin! 🚇 Try your luck today.',
        subject: 'MetroSafar Daily Spin',
      ),
    );
  }

  void _showAlreadySpunMessage() {
    if (!mounted || isSpinning) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('You have used today’s spin. Come back tomorrow!'),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final spinDisabled = isSpinning || hasSpunToday;

    return GameShell(
      title: 'Daily Spin',
      subtitle: showReward ? 'Great luck!' : 'Spin for rewards',
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s6,
            vertical: AppSpacing.s8,
          ),
          child: Column(
            children: [
              // Spin wheel
              Center(
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // Pointer (top)
                    Positioned(
                      top: 0,
                      child: CustomPaint(
                        painter: PointerPainter(),
                        size: const Size(20, 20),
                      ),
                    ),
                    // Wheel
                    RotationTransition(
                      turns: Tween<double>(begin: 0, end: 5).animate(
                        CurvedAnimation(
                          parent: _wheelController,
                          curve: Curves.easeOutCubic,
                        ),
                      ),
                      child: CustomPaint(
                        painter: SpinWheelPainter(
                          segments: segments,
                          selectedIndex: selectedSegmentIndex,
                        ),
                        size: const Size(280, 280),
                      ),
                    ),
                    // Center button
                    GestureDetector(
                      onTap: spinDisabled ? _showAlreadySpunMessage : _spin,
                      child: Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              AppColors.gradientStart,
                              AppColors.gradientEnd,
                            ],
                          ),
                          borderRadius: AppRadius.borderRadiusFull,
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.gradientStart.withValues(alpha: 0.3),
                              blurRadius: 20,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (isSpinning)
                              SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  valueColor: AlwaysStoppedAnimation(
                                    Colors.white,
                                  ),
                                  strokeWidth: 2,
                                ),
                              )
                            else
                              Text(
                                hasSpunToday ? 'DONE' : 'SPIN',
                                style: AppTypography.labelLarge.copyWith(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            if (!isSpinning && !hasSpunToday) ...[
                              const SizedBox(height: AppSpacing.s1),
                              Text(
                                '↻',
                                style: AppTypography.displaySmall.copyWith(
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.s8),
              // Info
              Container(
                padding: const EdgeInsets.all(AppSpacing.s4),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainer,
                  borderRadius: AppRadius.borderRadiusL,
                ),
                child: Column(
                  children: [
                    Text(
                      hasSpunToday ? 'Today’s spin used' : 'One free spin per day',
                      style: AppTypography.titleSmall.copyWith(
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.s2),
                    Text(
                      hasSpunToday
                          ? 'You won ${rewardSegment?.label ?? '$pointsEarned pts'}. Come back tomorrow for another chance.'
                          : 'Come back tomorrow for another chance to win!',
                      style: AppTypography.bodySmall.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SpinSegment {
  final String label;
  final String reward;
  final Color color;

  SpinSegment(this.label, this.reward, this.color);
}

class SpinWheelPainter extends CustomPainter {
  final List<SpinSegment> segments;
  final int selectedIndex;

  SpinWheelPainter({
    required this.segments,
    required this.selectedIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final paint = Paint()..style = PaintingStyle.fill;
    final strokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = Colors.white;

    const segmentAngle = 2 * 3.14159 / 8; // 360/8 segments

    for (int i = 0; i < segments.length; i++) {
      final startAngle = i * segmentAngle - 3.14159 / 2;
      final segment = segments[i];

      paint.color = segment.color;
      if (i == selectedIndex) {
        paint.color = segment.color.withValues(alpha: 1.0);
      }

      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        segmentAngle,
        true,
        paint,
      );

      // Segment border
      canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        segmentAngle,
        true,
        strokePaint,
      );

      // Text label
      final textPainter = TextPainter(
        text: TextSpan(
          text: segment.label,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 14,
            fontWeight: FontWeight.bold,
          ),
        ),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();

      final angle = startAngle + segmentAngle / 2;
      final labelRadius = radius * 0.65;
      final labelX = center.dx + labelRadius * cos(angle);
      final labelY = center.dy + labelRadius * sin(angle);

      canvas.save();
      canvas.translate(labelX, labelY);
      canvas.rotate(angle + 3.14159 / 2);
      textPainter.paint(
        canvas,
        Offset(-textPainter.width / 2, -textPainter.height / 2),
      );
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(SpinWheelPainter oldDelegate) => true;
}

class PointerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.gradientStart
      ..style = PaintingStyle.fill;

    final path = Path();
    path.moveTo(size.width / 2, 0);
    path.lineTo(0, size.height);
    path.lineTo(size.width, size.height);
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(PointerPainter oldDelegate) => false;
}

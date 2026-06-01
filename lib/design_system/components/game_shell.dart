import 'package:flutter/material.dart';
import '../tokens/colors.dart';
import '../tokens/radius.dart';
import '../tokens/spacing.dart';
import '../tokens/typography.dart';

/// Shared game shell providing consistent UI for all games
class GameShell extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget body;
  final Widget? bottomAction;
  final int? currentScore;
  final int? maxScore;
  final Duration? elapsedTime;
  final VoidCallback? onBack;
  final bool showTimer;

  const GameShell({
    required this.title,
    required this.body,
    this.subtitle,
    this.bottomAction,
    this.currentScore,
    this.maxScore,
    this.elapsedTime,
    this.onBack,
    this.showTimer = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          // Gradient header
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  AppColors.gradientStart,
                  AppColors.gradientEnd,
                ],
              ),
            ),
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.s4,
              AppSpacing.s2,
              AppSpacing.s4,
              AppSpacing.s6,
            ),
            child: SafeArea(
              bottom: false,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Back button
                  if (onBack != null)
                    GestureDetector(
                      onTap: onBack,
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: AppRadius.borderRadiusFull,
                        ),
                        child: Icon(
                          Icons.arrow_back,
                          color: Colors.white,
                        ),
                      ),
                    )
                  else
                    SizedBox(width: 40),
                  const SizedBox(width: AppSpacing.s4),
                  // Title
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: AppTypography.headlineMedium.copyWith(
                            color: Colors.white,
                          ),
                        ),
                        if (subtitle != null)
                          Text(
                            subtitle!,
                            style: AppTypography.labelMedium.copyWith(
                              color: Colors.white70,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s4),
                  // Score chip
                  if (currentScore != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.s3,
                        vertical: AppSpacing.s2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: AppRadius.borderRadiusFull,
                      ),
                      child: Text(
                        '$currentScore${maxScore != null ? '/$maxScore' : ''}',
                        style: AppTypography.labelLarge.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  // Timer chip
                  if (showTimer && elapsedTime != null)
                    SizedBox(width: AppSpacing.s3),
                  if (showTimer && elapsedTime != null)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.s3,
                        vertical: AppSpacing.s2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: AppRadius.borderRadiusFull,
                      ),
                      child: Text(
                        _formatDuration(elapsedTime!),
                        style: AppTypography.labelLarge.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          // Body
          Expanded(
            child: body,
          ),
          // Bottom action
          if (bottomAction != null)
            Padding(
              padding: const EdgeInsets.all(AppSpacing.s6),
              child: bottomAction!,
            ),
        ],
      ),
    );
  }

  String _formatDuration(Duration duration) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60);
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}

/// End-of-game bottom sheet
class GameEndBottomSheet extends StatelessWidget {
  final Widget? icon;
  final String title;
  final int score;
  final int points;
  final String? message;
  final List<Widget> actions;

  const GameEndBottomSheet({
    required this.title,
    required this.score,
    required this.points,
    required this.actions,
    this.icon,
    this.message,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            AppColors.gradientStart.withValues(alpha: 0.1),
            AppColors.gradientEnd.withValues(alpha: 0.05),
          ],
        ),
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(AppRadius.radius2XL),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          AppSpacing.s6,
          AppSpacing.s6,
          AppSpacing.s6,
          AppSpacing.s6 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon/Celebration
            if (icon != null) ...[
              SizedBox(height: 100, child: icon),
              const SizedBox(height: AppSpacing.s6),
            ],
            // Title
            Text(
              title,
              style: AppTypography.headlineLarge.copyWith(
                color: colorScheme.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.s4),
            // Score
            Container(
              padding: const EdgeInsets.all(AppSpacing.s4),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainer,
                borderRadius: AppRadius.borderRadiusL,
              ),
              child: Column(
                children: [
                  Text(
                    'Score',
                    style: AppTypography.bodySmall.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s2),
                  Text(
                    '$score',
                    style: AppTypography.displayMedium.copyWith(
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s3),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.s4,
                      vertical: AppSpacing.s2,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.goldPoints.withValues(alpha: 0.2),
                      borderRadius: AppRadius.borderRadiusS,
                    ),
                    child: Text(
                      '+$points points',
                      style: AppTypography.labelMedium.copyWith(
                        color: AppColors.goldPoints,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (message != null) ...[
              const SizedBox(height: AppSpacing.s4),
              Text(
                message!,
                style: AppTypography.bodyMedium.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            const SizedBox(height: AppSpacing.s8),
            // Actions
            ...actions,
          ],
        ),
      ),
    );
  }
}

/// Game answer chip with animation support
class GameAnswerChip extends StatefulWidget {
  final String label;
  final bool isSelected;
  final bool isCorrect;
  final VoidCallback onSelected;
  final Duration? delay;

  const GameAnswerChip({
    required this.label,
    required this.onSelected,
    this.isSelected = false,
    this.isCorrect = false,
    this.delay,
    super.key,
  });

  @override
  State<GameAnswerChip> createState() => _GameAnswerChipState();
}

class _GameAnswerChipState extends State<GameAnswerChip>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 0.95, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
    );

    if (widget.delay != null) {
      Future.delayed(widget.delay!, () {
        if (mounted) _controller.forward();
      });
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    Color backgroundColor = colorScheme.surfaceContainer;
    Color textColor = colorScheme.onSurface;
    BorderSide borderSide = BorderSide(color: colorScheme.outline.withValues(alpha: 0.3));

    if (widget.isSelected) {
      if (widget.isCorrect) {
        backgroundColor = AppColors.mintSuccess;
        textColor = Colors.white;
        borderSide = BorderSide(color: AppColors.mintSuccess);
      } else {
        backgroundColor = AppColors.danger;
        textColor = Colors.white;
        borderSide = BorderSide(color: AppColors.danger);
      }
    }

    return ScaleTransition(
      scale: _scaleAnimation,
      child: GestureDetector(
        onTap: widget.isSelected ? null : widget.onSelected,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s4,
            vertical: AppSpacing.s3,
          ),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: AppRadius.borderRadiusL,
            border: Border.fromBorderSide(borderSide),
          ),
          child: Text(
            widget.label,
            style: AppTypography.titleSmall.copyWith(
              color: textColor,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

const Color danger = Color(0xFFEF4444);

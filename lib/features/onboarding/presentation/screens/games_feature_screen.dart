import 'package:flutter/material.dart';


import '../../../../design_system/tokens/spacing.dart';
import '../../../../design_system/tokens/typography.dart';

class GamesFeatureScreen extends StatelessWidget {
  final VoidCallback onNext;
  final VoidCallback onBack;

  const GamesFeatureScreen({
    required this.onNext,
    required this.onBack,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.s6),
          child: Column(
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '🎮',
                      style: AppTypography.displayLarge.copyWith(fontSize: 100),
                    ),
                    const SizedBox(height: AppSpacing.s6),
                    Text(
                      'Play & Earn',
                      style: AppTypography.headlineLarge.copyWith(
                        color: colorScheme.onSurface,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.s4),
                    Text(
                      'Play 5 exciting games daily:\n\n🎡 Daily Spin\n🧠 Trivia Quiz\n🎯 Sudoku\n🧩 Word Puzzle\n🗺️ City Explorer\n\nEarn points with every game!',
                      style: AppTypography.bodyLarge.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onBack,
                      child: const Text('Back'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s4),
                  Expanded(
                    child: FilledButton(
                      onPressed: onNext,
                      child: const Text('Next'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

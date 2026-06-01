import 'package:flutter/material.dart';

import '../../../design_system/tokens/spacing.dart';
import '../../../design_system/tokens/typography.dart';

class CommuteEndSummary extends StatelessWidget {
  final int pointsEarned;
  final VoidCallback onClose;

  const CommuteEndSummary({
    required this.pointsEarned,
    required this.onClose,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.s6,
        AppSpacing.s6,
        AppSpacing.s6,
        AppSpacing.s6 + MediaQuery.of(context).padding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('🚇', style: TextStyle(fontSize: 52)),
          const SizedBox(height: AppSpacing.s3),
          Text('Commute complete', style: AppTypography.headlineSmall),
          const SizedBox(height: AppSpacing.s2),
          Text(
            pointsEarned > 0
                ? 'You earned $pointsEarned bonus points this ride.'
                : 'Activities during commute mode earned a 1.5x multiplier.',
            textAlign: TextAlign.center,
            style: AppTypography.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.s6),
          SizedBox(
            width: double.infinity,
            child: FilledButton(onPressed: onClose, child: const Text('Nice')),
          ),
        ],
      ),
    );
  }
}

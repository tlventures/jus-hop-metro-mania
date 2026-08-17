import 'package:flutter/material.dart';

import '../../../../design_system/tokens/radius.dart';
import '../../../../design_system/tokens/spacing.dart';
import '../../../../design_system/tokens/typography.dart';

/// Terminal screen for users who declare they are under 18.
///
/// MetroSafar does not process personal data of children, so rather than
/// collecting a guardian's contact details for verifiable parental consent
/// (DPDPA §9), the app stops here. Nothing beyond the locally stored date of
/// birth is collected, and no account is created.
///
/// There is deliberately no bypass: no skip, no forward navigation, and
/// [PopScope] blocks the system back gesture. The only way out is to correct a
/// mistyped birthday via [onChangeDob].
class AgeRestrictedScreen extends StatelessWidget {
  final VoidCallback onChangeDob;

  const AgeRestrictedScreen({required this.onChangeDob, super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.s6),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(AppSpacing.s5),
                  decoration: BoxDecoration(
                    color: cs.secondaryContainer,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.shield_outlined,
                      size: 48, color: cs.onSecondaryContainer),
                ),
                const SizedBox(height: AppSpacing.s6),
                Text(
                  'MetroSafar is for ages 18 and over',
                  textAlign: TextAlign.center,
                  style: AppTypography.headlineMedium.copyWith(
                    color: cs.onSurface,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: AppSpacing.s3),
                Text(
                  "Thanks for your interest. We're not able to offer MetroSafar "
                  'to under-18s right now, so we have stopped here rather than '
                  'collect any more of your information.',
                  textAlign: TextAlign.center,
                  style: AppTypography.bodyMedium
                      .copyWith(color: cs.onSurfaceVariant),
                ),
                const SizedBox(height: AppSpacing.s5),
                Container(
                  padding: const EdgeInsets.all(AppSpacing.s4),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: AppRadius.borderRadiusXL,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.lock_outline,
                          size: 20, color: cs.onSurfaceVariant),
                      const SizedBox(width: AppSpacing.s3),
                      Expanded(
                        child: Text(
                          'Your date of birth stayed on this device. No account '
                          'was created and nothing was sent to our servers.',
                          style: AppTypography.bodySmall
                              .copyWith(color: cs.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.s6),
                TextButton(
                  onPressed: onChangeDob,
                  child: const Text('I entered my birthday incorrectly'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../design_system/tokens/colors.dart';
import '../../../design_system/tokens/radius.dart';
import '../../../design_system/tokens/spacing.dart';
import '../../../design_system/tokens/typography.dart';
import '../application/referral_provider.dart';

class ReferralScreen extends ConsumerStatefulWidget {
  const ReferralScreen({super.key});

  @override
  ConsumerState<ReferralScreen> createState() => _ReferralScreenState();
}

class _ReferralScreenState extends ConsumerState<ReferralScreen> {
  final _codeController = TextEditingController();

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(referralProvider.notifier).load());
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(referralProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Invite Friends')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.s6),
        children: [
          Container(
            padding: const EdgeInsets.all(AppSpacing.s6),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [AppColors.gradientStart, AppColors.gradientEnd],
              ),
              borderRadius: AppRadius.borderRadiusXL,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Give 100, get 150',
                  style: AppTypography.headlineSmall.copyWith(
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: AppSpacing.s2),
                Text(
                  'Your friend gets a welcome bonus after their first game or trip. You get rewarded when they qualify.',
                  style: AppTypography.bodyMedium.copyWith(
                    color: Colors.white.withValues(alpha: 0.86),
                  ),
                ),
                const SizedBox(height: AppSpacing.s5),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSpacing.s4),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.16),
                    borderRadius: AppRadius.borderRadiusL,
                  ),
                  child: Text(
                    state.code ??
                        (state.isLoading
                            ? 'Loading...'
                            : 'Tap refresh to create code'),
                    textAlign: TextAlign.center,
                    style: AppTypography.headlineSmall.copyWith(
                      color: Colors.white,
                      letterSpacing: 1.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.s4),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed:
                            state.shareMessage == null
                                ? null
                                : () => SharePlus.instance.share(
                                  ShareParams(
                                    text: state.shareMessage!,
                                    subject: 'Join me on MetroSafar',
                                  ),
                                ),
                        icon: const Icon(Icons.ios_share),
                        label: const Text('Share'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.s3),
                    IconButton.filledTonal(
                      onPressed:
                          state.code == null
                              ? null
                              : () {
                                Clipboard.setData(
                                  ClipboardData(text: state.code!),
                                );
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Referral code copied'),
                                  ),
                                );
                              },
                      icon: const Icon(Icons.copy),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.s6),
          Row(
            children: [
              Expanded(
                child: _ReferralMetric(
                  label: 'Used',
                  value: '${state.usedCount}',
                ),
              ),
              const SizedBox(width: AppSpacing.s3),
              Expanded(
                child: _ReferralMetric(
                  label: 'Rewarded',
                  value: '${state.rewardedCount}',
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s8),
          Text(
            'Have a code?',
            style: AppTypography.titleMedium.copyWith(
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: AppSpacing.s3),
          TextField(
            controller: _codeController,
            textCapitalization: TextCapitalization.characters,
            decoration: const InputDecoration(
              hintText: 'METRO-XK9F2',
              prefixIcon: Icon(Icons.confirmation_number_outlined),
            ),
          ),
          const SizedBox(height: AppSpacing.s3),
          FilledButton(
            onPressed:
                state.isLoading
                    ? null
                    : () async {
                      final ok = await ref
                          .read(referralProvider.notifier)
                          .apply(_codeController.text.trim());
                      if (!context.mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            ok
                                ? 'Referral applied and friend added'
                                : 'Could not apply this code',
                          ),
                        ),
                      );
                    },
            child: const Text('Apply Code'),
          ),
          if (state.error != null) ...[
            const SizedBox(height: AppSpacing.s4),
            Text(state.error!, style: TextStyle(color: colorScheme.error)),
          ],
        ],
      ),
    );
  }
}

class _ReferralMetric extends StatelessWidget {
  final String label;
  final String value;

  const _ReferralMetric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.s4),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainer,
        borderRadius: AppRadius.borderRadiusL,
      ),
      child: Column(
        children: [
          Text(
            value,
            style: AppTypography.headlineSmall.copyWith(
              color: colorScheme.onSurface,
            ),
          ),
          Text(
            label,
            style: AppTypography.labelMedium.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

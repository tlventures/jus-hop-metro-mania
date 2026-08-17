// lib/features/wallet/presentation/promo_redeem_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../design_system/tokens/colors.dart';
import '../../../design_system/tokens/radius.dart';
import '../../../design_system/tokens/spacing.dart';
import '../../../design_system/tokens/typography.dart';
import '../application/promo_provider.dart';
import '../data/promo_service.dart';

class PromoRedeemScreen extends ConsumerStatefulWidget {
  const PromoRedeemScreen({super.key});

  @override
  ConsumerState<PromoRedeemScreen> createState() => _PromoRedeemScreenState();
}

class _PromoRedeemScreenState extends ConsumerState<PromoRedeemScreen> {
  int _pointsToRedeem = 0;
  bool _busy = false;
  String? _error;
  PromoCodeItem? _lastMinted;

  int _snap(int v, int max) {
    // Round down to nearest multiple of 10 so backend accepts it.
    final n = (v ~/ 10) * 10;
    return n.clamp(0, max);
  }

  Future<void> _redeem() async {
    if (_pointsToRedeem < 10) return;
    setState(() { _busy = true; _error = null; _lastMinted = null; });
    try {
      final code = await ref.read(promoServiceProvider).redeem(_pointsToRedeem);
      if (!mounted) return;
      // Refresh caches so both balance + codes list reflect the new state.
      ref.invalidate(walletBalanceProvider);
      ref.invalidate(promoCodesProvider);
      setState(() {
        _lastMinted = code;
        _pointsToRedeem = 0;
        _busy = false;
      });
    } on PromoApiException catch (e) {
      setState(() { _error = e.message; _busy = false; });
    } catch (e) {
      setState(() { _error = 'Could not redeem points. Try again.'; _busy = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final balanceAsync = ref.watch(walletBalanceProvider);
    final codesAsync = ref.watch(promoCodesProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text('Redeem Points', style: AppTypography.headlineMedium),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(walletBalanceProvider);
          ref.invalidate(promoCodesProvider);
        },
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.s4),
          children: [
            balanceAsync.when(
              loading: () => const _BalanceSkeleton(),
              error: (e, _) => _BalanceError(message: '$e'),
              data: (bal) => _BalanceCard(balance: bal),
            ),

            const SizedBox(height: AppSpacing.s4),

            balanceAsync.maybeWhen(
              data: (bal) => _RedeemSlider(
                balance: bal,
                value: _pointsToRedeem,
                onChanged: (v) => setState(() =>
                    _pointsToRedeem = _snap(v.round(), bal.points)),
              ),
              orElse: () => const SizedBox.shrink(),
            ),

            const SizedBox(height: AppSpacing.s4),

            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(AppSpacing.s3),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.08),
                  borderRadius: AppRadius.borderRadiusM,
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_error!, style: const TextStyle(color: Colors.red))),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.s3),
            ],

            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
                  shape: RoundedRectangleBorder(
                    borderRadius: AppRadius.borderRadiusL,
                  ),
                ),
                onPressed: (_busy || _pointsToRedeem < 10) ? null : _redeem,
                icon: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.card_giftcard_rounded),
                label: Text(
                  _busy
                      ? 'Redeeming…'
                      : _pointsToRedeem < 10
                          ? 'Pick at least 10 points'
                          : 'Get promo code · ₹${(_pointsToRedeem / 10).toStringAsFixed(2)}',
                  style: AppTypography.titleMedium.copyWith(color: Colors.white),
                ),
              ),
            ),

            if (_lastMinted != null) ...[
              const SizedBox(height: AppSpacing.s4),
              _MintedCodeCard(code: _lastMinted!),
            ],

            const SizedBox(height: AppSpacing.s6),
            Text('Your codes', style: AppTypography.titleMedium),
            const SizedBox(height: AppSpacing.s3),

            codesAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => Text('Could not load codes.', style: TextStyle(color: cs.error)),
              data: (codes) {
                if (codes.isEmpty) {
                  return Text(
                    'No codes yet. Redeem points above to mint your first one.',
                    style: AppTypography.bodySmall.copyWith(color: cs.onSurfaceVariant),
                  );
                }
                return Column(children: codes.map((c) => _CodeRow(code: c)).toList());
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.balance});
  final WalletBalance balance;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.s5),
      decoration: BoxDecoration(
        borderRadius: AppRadius.borderRadiusL,
        gradient: LinearGradient(
          colors: [
            AppColors.primary.withValues(alpha: 0.95),
            AppColors.electricTeal.withValues(alpha: 0.90),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Available balance',
            style: AppTypography.bodyMedium.copyWith(
              color: Colors.white.withValues(alpha: 0.85),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${balance.points} pts',
            style: AppTypography.headlineMedium.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '= ₹${balance.inrEquivalent.toStringAsFixed(2)} in ticket credit',
            style: AppTypography.bodyMedium.copyWith(color: Colors.white),
          ),
          if (balance.nextExpiryPoints > 0 && balance.nextExpiryAt != null) ...[
            const SizedBox(height: AppSpacing.s3),
            Text(
              '${balance.nextExpiryPoints} pts expire on ${balance.nextExpiryAt!.toLocal().toString().split(' ').first}',
              style: AppTypography.bodySmall.copyWith(
                color: Colors.white.withValues(alpha: 0.85),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _BalanceSkeleton extends StatelessWidget {
  const _BalanceSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 130,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
        borderRadius: AppRadius.borderRadiusL,
      ),
      child: const Center(child: CircularProgressIndicator()),
    );
  }
}

class _BalanceError extends StatelessWidget {
  const _BalanceError({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.s4),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.08),
        borderRadius: AppRadius.borderRadiusL,
      ),
      child: Text('Balance unavailable · $message',
          style: const TextStyle(color: Colors.red)),
    );
  }
}

class _RedeemSlider extends StatelessWidget {
  const _RedeemSlider({
    required this.balance,
    required this.value,
    required this.onChanged,
  });
  final WalletBalance balance;
  final int value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (balance.points < 10) {
      return Container(
        padding: const EdgeInsets.all(AppSpacing.s4),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: AppRadius.borderRadiusL,
        ),
        child: Text(
          'You need at least 10 points to mint a code. Book a ticket to earn '
          'more.',
          style: AppTypography.bodyMedium.copyWith(color: cs.onSurfaceVariant),
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(AppSpacing.s4),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: AppRadius.borderRadiusL,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Points to redeem', style: AppTypography.titleMedium),
              const Spacer(),
              Text(
                '$value pts',
                style: AppTypography.titleMedium.copyWith(
                  fontWeight: FontWeight.w800,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
          Slider(
            value: value.toDouble(),
            min: 0,
            max: balance.points.toDouble(),
            divisions:
                balance.points >= 10 ? (balance.points ~/ 10).clamp(1, 200) : 1,
            label: '$value pts',
            onChanged: onChanged,
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('0', style: AppTypography.bodySmall),
              Text('₹${(value / 10).toStringAsFixed(2)}',
                  style: AppTypography.bodyMedium.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.primary,
                  )),
              Text('${balance.points} pts',
                  style: AppTypography.bodySmall),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Codes are single-use, valid for 30 days, and cap the discount at '
            '50% of the ticket price.',
            style: AppTypography.bodySmall.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _MintedCodeCard extends StatelessWidget {
  const _MintedCodeCard({required this.code});
  final PromoCodeItem code;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.s4),
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.10),
        borderRadius: AppRadius.borderRadiusL,
        border: Border.all(color: Colors.green.withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: Colors.green),
              const SizedBox(width: 8),
              Text('Code ready!',
                  style: AppTypography.titleMedium
                      .copyWith(fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: AppSpacing.s3),
          Row(
            children: [
              Expanded(
                child: SelectableText(
                  code.code,
                  style: AppTypography.titleLarge.copyWith(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.copy_rounded),
                tooltip: 'Copy',
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: code.code));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Code copied')),
                    );
                  }
                },
              ),
            ],
          ),
          Text('Worth ₹${code.valueInr.toStringAsFixed(2)} · Expires '
              '${code.expiresAt.toLocal().toString().split(' ').first}'),
        ],
      ),
    );
  }
}

class _CodeRow extends StatelessWidget {
  const _CodeRow({required this.code});
  final PromoCodeItem code;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isActive = code.isActive;
    final statusColor = isActive
        ? Colors.green
        : (code.status == 'USED' ? cs.onSurfaceVariant : Colors.orange);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.borderRadiusM,
        side: BorderSide(color: cs.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s3),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    code.code,
                    style: AppTypography.titleMedium.copyWith(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    '₹${code.valueInr.toStringAsFixed(2)} · '
                    '${isActive ? "expires ${code.expiresAt.toLocal().toString().split(' ').first}" : code.status.toLowerCase()}',
                    style: AppTypography.bodySmall
                        .copyWith(color: statusColor),
                  ),
                ],
              ),
            ),
            if (isActive)
              IconButton(
                icon: const Icon(Icons.copy_rounded),
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: code.code));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Code copied')),
                    );
                  }
                },
              ),
          ],
        ),
      ),
    );
  }
}

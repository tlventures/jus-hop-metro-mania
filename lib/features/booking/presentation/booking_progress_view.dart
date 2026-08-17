// lib/features/booking/presentation/booking_progress_view.dart

import 'package:flutter/material.dart';

import '../../../design_system/tokens/colors.dart';
import '../../../design_system/tokens/radius.dart';
import '../../../design_system/tokens/spacing.dart';
import '../../../design_system/tokens/typography.dart';
import '../application/ticketing_provider.dart';

/// Two-phase confirmation timeline shown after payment succeeds:
///
///   1. Payment received
///   2. Requesting ticket from Hyderabad Metro
///   3. Ticket confirmed   — OR —   Refund initiated (if issuance failed)
///
/// Metro ticketing is two-phase: money is taken first, then the metro issues
/// the QR. If step 3 fails, the payment is refunded automatically — this view
/// makes that promise visible instead of showing a bare error.
class BookingProgressView extends StatelessWidget {
  const BookingProgressView({
    super.key,
    required this.status,
    required this.fromStation,
    required this.toStation,
    required this.fareLabel,
    this.refundReference,
    this.onDone,
  });

  final BookingStatus status;
  final String fromStation;
  final String toStation;
  final String fareLabel;
  final String? refundReference;

  /// Shown as a button on the terminal refund screen (e.g. back to Home).
  final VoidCallback? onDone;

  bool get _isRefund => status == BookingStatus.refundInitiated;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // Phase completion is derived from the state machine.
    const paidStates = {
      BookingStatus.paymentVerifying,
      BookingStatus.ticketConfirmed,
      BookingStatus.refundInitiated,
    };
    final paid = paidStates.contains(status);
    final issuing = status == BookingStatus.paymentVerifying;
    final confirmed = status == BookingStatus.ticketConfirmed;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s5),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _isRefund ? 'Refunding your payment' : 'Processing your ticket',
              style: AppTypography.headlineSmall.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: AppSpacing.s6),

            // The timeline.
            _Phase(
              label: 'Payment received',
              state: paid ? _StepState.done : _StepState.active,
              isFirst: true,
            ),
            _Phase(
              label: _isRefund
                  ? 'Ticket could not be issued'
                  : 'Requesting ticket from Hyderabad Metro',
              state: _isRefund
                  ? _StepState.failed
                  : issuing
                      ? _StepState.active
                      : confirmed
                          ? _StepState.done
                          : _StepState.pending,
            ),
            _Phase(
              label: _isRefund ? 'Refund initiated' : 'Booking confirmed',
              state: _isRefund
                  ? _StepState.refund
                  : confirmed
                      ? _StepState.done
                      : _StepState.pending,
              isLast: true,
            ),

            const SizedBox(height: AppSpacing.s6),

            // Trip + fare summary (Rapido-style footer).
            Container(
              padding: const EdgeInsets.all(AppSpacing.s4),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHigh,
                borderRadius: AppRadius.borderRadiusL,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _StationLine(color: Colors.green, label: fromStation),
                  Padding(
                    padding: const EdgeInsets.only(left: 5, top: 2, bottom: 2),
                    child: Container(width: 2, height: 14, color: cs.outlineVariant),
                  ),
                  _StationLine(color: Colors.redAccent, label: toStation),
                  const Divider(height: AppSpacing.s5),
                  Row(
                    children: [
                      Text('Total fare',
                          style: AppTypography.bodyMedium
                              .copyWith(color: cs.onSurfaceVariant)),
                      const Spacer(),
                      Text(fareLabel,
                          style: AppTypography.titleMedium
                              .copyWith(fontWeight: FontWeight.w800)),
                    ],
                  ),
                ],
              ),
            ),

            if (_isRefund) ...[
              const SizedBox(height: AppSpacing.s4),
              Container(
                padding: const EdgeInsets.all(AppSpacing.s4),
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.08),
                  borderRadius: AppRadius.borderRadiusM,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.verified_user_outlined,
                        size: 20, color: AppColors.primary),
                    const SizedBox(width: AppSpacing.s3),
                    Expanded(
                      child: Text(
                        'Your money is safe. The full amount will be returned to '
                        'your payment method automatically, usually within 3–5 '
                        'working days.'
                        '${refundReference != null ? '\nRef: $refundReference' : ''}',
                        style: AppTypography.bodySmall
                            .copyWith(color: cs.onSurface),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const Spacer(),

            if (_isRefund && onDone != null)
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: onDone,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                  ),
                  child: const Text('Back to Home'),
                ),
              )
            else if (!confirmed)
              Center(
                child: Text(
                  'Please keep the app open…',
                  style: AppTypography.bodySmall.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

enum _StepState { pending, active, done, failed, refund }

class _Phase extends StatelessWidget {
  const _Phase({
    required this.label,
    required this.state,
    this.isFirst = false,
    this.isLast = false,
  });

  final String label;
  final _StepState state;
  final bool isFirst;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final (Color color, Widget marker) = switch (state) {
      _StepState.done => (
          Colors.green,
          const Icon(Icons.check, size: 16, color: Colors.white),
        ),
      _StepState.active => (
          AppColors.primary,
          const SizedBox(
            width: 14,
            height: 14,
            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
          ),
        ),
      _StepState.failed => (
          Colors.redAccent,
          const Icon(Icons.close, size: 16, color: Colors.white),
        ),
      _StepState.refund => (
          AppColors.primary,
          const Icon(Icons.replay, size: 16, color: Colors.white),
        ),
      _StepState.pending => (cs.outlineVariant, const SizedBox.shrink()),
    };

    final bool muted = state == _StepState.pending;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              Container(
                width: 2,
                height: 10,
                color: isFirst ? Colors.transparent : cs.outlineVariant,
              ),
              Container(
                width: 26,
                height: 26,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                child: marker,
              ),
              Expanded(
                child: Container(
                  width: 2,
                  color: isLast ? Colors.transparent : cs.outlineVariant,
                ),
              ),
            ],
          ),
          const SizedBox(width: AppSpacing.s3),
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: AppSpacing.s3),
            child: Text(
              label,
              style: AppTypography.titleMedium.copyWith(
                fontWeight: muted ? FontWeight.w500 : FontWeight.w700,
                color: muted ? cs.onSurfaceVariant : cs.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StationLine extends StatelessWidget {
  const _StationLine({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.circle, size: 12, color: color),
        const SizedBox(width: AppSpacing.s3),
        Expanded(
          child: Text(
            label,
            style: AppTypography.bodyMedium.copyWith(fontWeight: FontWeight.w600),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

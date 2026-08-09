// lib/features/booking/presentation/booking_checkout_screen.dart

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

import '../../../design_system/tokens/colors.dart';
import '../../../design_system/tokens/radius.dart';
import '../../../design_system/tokens/spacing.dart';
import '../../../design_system/tokens/typography.dart';
import '../application/ticketing_provider.dart';

/// Booking checkout for unreserved SJT/RJT tickets.
///
/// Metro tickets are not passenger-bound — the QR is scanned at the turnstile
/// and any valid holder can use it. So we don't ask the user for name/phone
/// here. The ONDC billing block still needs *something*, so we quietly fill it
/// from the signed-in Firebase profile.
class BookingCheckoutScreen extends ConsumerStatefulWidget {
  const BookingCheckoutScreen({super.key});

  @override
  ConsumerState<BookingCheckoutScreen> createState() => _BookingCheckoutScreenState();
}

class _BookingCheckoutScreenState extends ConsumerState<BookingCheckoutScreen> {
  late final Razorpay _razorpay;
  final _promoController = TextEditingController();
  bool _promoExpanded = false;

  @override
  void initState() {
    super.initState();
    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _onPaymentSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _onPaymentError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _onExternalWallet);
  }

  @override
  void dispose() {
    _promoController.dispose();
    _razorpay.clear();
    super.dispose();
  }

  ({String name, String phone, String? email}) _autoFillFromFirebase() {
    final user = FirebaseAuth.instance.currentUser;
    final displayName = user?.displayName?.trim();
    final name = (displayName != null && displayName.isNotEmpty)
        ? displayName
        : 'MetroSafar Passenger';
    // Firebase phone is not always available for email-authed users. Use a
    // spec-compliant placeholder that still passes ONDC's format check.
    final phone = user?.phoneNumber?.trim().isNotEmpty == true
        ? user!.phoneNumber!
        : '+91-9999999999';
    final email = user?.email;
    return (name: name, phone: phone, email: email);
  }

  Future<void> _startCheckout() async {
    final auto = _autoFillFromFirebase();
    final promo = _promoController.text.trim();
    final checkout = await ref.read(ticketingNotifierProvider.notifier).prepareRazorpayCheckout(
          autoName: auto.name,
          autoPhone: auto.phone,
          autoEmail: auto.email,
          promoCode: promo.isEmpty ? null : promo.toUpperCase(),
        );
    if (checkout == null || !mounted) return;

    final options = <String, dynamic>{
      'key': checkout.razorpayKeyId,
      'order_id': checkout.razorpayOrderId,
      'amount': checkout.amountInPaise,
      'currency': checkout.currency,
      'name': 'MetroSafar',
      'description': 'Hyderabad Metro ticket',
      'prefill': {
        'name': checkout.prefillName,
        'contact': checkout.prefillPhone,
        if (checkout.prefillEmail != null) 'email': checkout.prefillEmail,
      },
      'theme': {'color': '#0066CC'},
    };

    try {
      _razorpay.open(options);
    } catch (e) {
      if (kDebugMode) debugPrint('Razorpay open error: $e');
      ref.read(ticketingNotifierProvider.notifier).reportPaymentFailed('Could not launch payment.');
    }
  }

  Future<void> _onPaymentSuccess(PaymentSuccessResponse response) async {
    final notifier = ref.read(ticketingNotifierProvider.notifier);
    final orderId = response.orderId ?? ref.read(ticketingNotifierProvider).pendingCheckout?.razorpayOrderId;
    final paymentId = response.paymentId;
    final signature = response.signature;
    if (orderId == null || paymentId == null || signature == null) {
      notifier.reportPaymentFailed('Payment response missing signature.');
      return;
    }
    final ok = await notifier.completePaymentAndConfirm(
      razorpayOrderId: orderId,
      razorpayPaymentId: paymentId,
      razorpaySignature: signature,
    );
    if (ok && mounted) context.go('/booking/ticket');
  }

  void _onPaymentError(PaymentFailureResponse response) {
    if (response.code == 2) {
      ref.read(ticketingNotifierProvider.notifier).reportPaymentCancelled();
    } else {
      ref.read(ticketingNotifierProvider.notifier).reportPaymentFailed(response.message);
    }
  }

  void _onExternalWallet(ExternalWalletResponse response) {
    ref.read(ticketingNotifierProvider.notifier).reportPaymentCancelled();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final state = ref.watch(ticketingNotifierProvider);
    final option = state.selectedOption;
    final displayAmount = (option?.fare ?? 0) * state.passengerCount;

    final isBusy = state.status == BookingStatus.bookingInInit
        || state.status == BookingStatus.paymentPending
        || state.status == BookingStatus.paymentVerifying;

    return Scaffold(
      appBar: AppBar(
        title: Text('Checkout', style: AppTypography.headlineMedium),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.s4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Trip summary
              Container(
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
                        const Icon(
                          Icons.confirmation_number_outlined,
                          color: AppColors.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            option?.title ?? 'Metro Ticket',
                            style: AppTypography.titleMedium.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.s3),
                    _KVRow(
                      label: 'From',
                      value: state.originStation?.name ?? '—',
                    ),
                    const SizedBox(height: 6),
                    _KVRow(
                      label: 'To',
                      value: state.destinationStation?.name ?? '—',
                    ),
                    const SizedBox(height: 6),
                    _KVRow(
                      label: 'Passengers',
                      value: '${state.passengerCount}',
                      trailing: _PaxStepper(
                        value: state.passengerCount,
                        onChanged: (v) => ref
                            .read(ticketingNotifierProvider.notifier)
                            .setPassengerCount(v),
                      ),
                    ),
                    const Divider(height: AppSpacing.s6),
                    Row(
                      children: [
                        Text(
                          'Total',
                          style: AppTypography.titleMedium.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '₹${displayAmount.toStringAsFixed(0)}',
                          style: AppTypography.headlineMedium.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Final amount is confirmed by the payment gateway before charge.',
                      style: AppTypography.bodySmall.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: AppSpacing.s3),

              // Collapsible promo code row.
              InkWell(
                onTap: () => setState(() => _promoExpanded = !_promoExpanded),
                borderRadius: AppRadius.borderRadiusM,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.s2),
                  child: Row(
                    children: [
                      Icon(Icons.local_offer_outlined,
                          size: 18, color: cs.onSurfaceVariant),
                      const SizedBox(width: 8),
                      Text(
                        _promoController.text.isEmpty
                            ? 'Have a promo code?'
                            : 'Promo: ${_promoController.text.toUpperCase()}',
                        style: AppTypography.bodyMedium
                            .copyWith(color: AppColors.primary),
                      ),
                      const Spacer(),
                      Icon(
                        _promoExpanded
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                        color: cs.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
              if (_promoExpanded)
                TextField(
                  controller: _promoController,
                  textCapitalization: TextCapitalization.characters,
                  decoration: InputDecoration(
                    hintText: 'e.g. SAFAR-ABCD1234',
                    border: OutlineInputBorder(
                      borderRadius: AppRadius.borderRadiusM,
                    ),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.s3,
                      vertical: AppSpacing.s3,
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              const SizedBox(height: AppSpacing.s3),

              Text(
                'Unreserved ticket — no passenger details required. QR is valid for any single-trip use within 4 hours.',
                style: AppTypography.bodySmall.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),

              if (state.errorMessage != null) ...[
                const SizedBox(height: AppSpacing.s4),
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
                      Expanded(
                        child: Text(
                          state.errorMessage!,
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const Spacer(),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
                    shape: RoundedRectangleBorder(
                      borderRadius: AppRadius.borderRadiusL,
                    ),
                  ),
                  onPressed: isBusy ? null : _startCheckout,
                  child: isBusy
                      ? Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Text(
                              state.status == BookingStatus.paymentVerifying
                                  ? 'Verifying payment…'
                                  : state.status == BookingStatus.paymentPending
                                      ? 'Waiting for Razorpay…'
                                      : 'Preparing order…',
                            ),
                          ],
                        )
                      : Text(
                          'Pay ₹${displayAmount.toStringAsFixed(0)} & Book',
                          style: AppTypography.titleMedium.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _KVRow extends StatelessWidget {
  const _KVRow({required this.label, required this.value, this.trailing});
  final String label;
  final String value;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Text(
          label,
          style: AppTypography.bodyMedium.copyWith(color: cs.onSurfaceVariant),
        ),
        const Spacer(),
        if (trailing != null)
          trailing!
        else
          Flexible(
            child: Text(
              value,
              style: AppTypography.bodyMedium.copyWith(fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
            ),
          ),
      ],
    );
  }
}

class _PaxStepper extends StatelessWidget {
  const _PaxStepper({required this.value, required this.onChanged});
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget btn(IconData icon, VoidCallback? onTap) => InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(999),
          child: Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: onTap == null
                  ? cs.surfaceContainerHighest
                  : cs.primaryContainer,
            ),
            child: Icon(icon, size: 16, color: cs.onPrimaryContainer),
          ),
        );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        btn(Icons.remove, value > 1 ? () => onChanged(value - 1) : null),
        SizedBox(
          width: 28,
          child: Text(
            '$value',
            textAlign: TextAlign.center,
            style: AppTypography.titleMedium.copyWith(fontWeight: FontWeight.w700),
          ),
        ),
        btn(Icons.add, value < 6 ? () => onChanged(value + 1) : null),
      ],
    );
  }
}

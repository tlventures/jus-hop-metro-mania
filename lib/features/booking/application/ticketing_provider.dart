// lib/features/booking/application/ticketing_provider.dart

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../models/metro_station.dart';
import '../data/ticketing_service.dart';
import '../domain/ticketing_models.dart';

/// Static catalog of ticket options. The BPP's `on_search` callback is the
/// eventual authoritative source, but the app renders these deterministically
/// so the UI never dead-ends on a slow / failing / unauthenticated search.
/// Fares here are advisory — the authoritative amount comes from the Razorpay
/// order created server-side from the txn quote.
final List<RouteOption> _defaultRouteCatalog = const [
  RouteOption(
    id: 'I1',
    title: 'Single Journey Ticket (SJT)',
    type: 'SJT',
    fare: 35.0,
    totalDurationMinutes: 24,
    totalStops: 8,
  ),
  RouteOption(
    id: 'I2',
    title: 'Return Journey Ticket (RJT)',
    type: 'RJT',
    fare: 60.0,
    totalDurationMinutes: 24,
    totalStops: 8,
  ),
];

final ticketingServiceProvider = Provider<TicketingService>((ref) {
  return TicketingService();
});

enum BookingStatus {
  idle,
  searching,
  routesLoaded,
  bookingInInit,
  paymentPending,
  paymentVerifying,
  ticketConfirmed,
  error,
}

class RazorpayCheckout {
  final String razorpayKeyId;
  final String razorpayOrderId;
  final int amountInPaise;
  final String currency;
  final String prefillName;
  final String prefillPhone;
  final String? prefillEmail;

  const RazorpayCheckout({
    required this.razorpayKeyId,
    required this.razorpayOrderId,
    required this.amountInPaise,
    required this.currency,
    required this.prefillName,
    required this.prefillPhone,
    this.prefillEmail,
  });
}

class TicketingState {
  final BookingStatus status;
  final MetroStation? originStation;
  final MetroStation? destinationStation;
  final String? transactionId;
  final List<RouteOption> availableOptions;
  final RouteOption? selectedOption;
  final int passengerCount;
  final String passengerName;
  final String passengerPhone;
  final MetroTicket? activeTicket;
  final String? errorMessage;
  final RazorpayCheckout? pendingCheckout;

  const TicketingState({
    this.status = BookingStatus.idle,
    this.originStation,
    this.destinationStation,
    this.transactionId,
    this.availableOptions = const [],
    this.selectedOption,
    this.passengerCount = 1,
    this.passengerName = '',
    this.passengerPhone = '',
    this.activeTicket,
    this.errorMessage,
    this.pendingCheckout,
  });

  TicketingState copyWith({
    BookingStatus? status,
    MetroStation? originStation,
    MetroStation? destinationStation,
    String? transactionId,
    List<RouteOption>? availableOptions,
    RouteOption? selectedOption,
    int? passengerCount,
    String? passengerName,
    String? passengerPhone,
    MetroTicket? activeTicket,
    String? errorMessage,
    RazorpayCheckout? pendingCheckout,
    bool clearError = false,
    bool clearCheckout = false,
  }) {
    return TicketingState(
      status: status ?? this.status,
      originStation: originStation ?? this.originStation,
      destinationStation: destinationStation ?? this.destinationStation,
      transactionId: transactionId ?? this.transactionId,
      availableOptions: availableOptions ?? this.availableOptions,
      selectedOption: selectedOption ?? this.selectedOption,
      passengerCount: passengerCount ?? this.passengerCount,
      passengerName: passengerName ?? this.passengerName,
      passengerPhone: passengerPhone ?? this.passengerPhone,
      activeTicket: activeTicket ?? this.activeTicket,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      pendingCheckout: clearCheckout ? null : (pendingCheckout ?? this.pendingCheckout),
    );
  }
}

/// Indian mobile: exactly 10 digits, starts with 6-9. Rejects the default
/// "9876543210" that used to be pre-filled.
final RegExp _indianMobileRe = RegExp(r'^[6-9]\d{9}$');
const String _blockedDefaultPhone = '9876543210';

String? validatePassengerName(String? v) {
  final trimmed = (v ?? '').trim();
  if (trimmed.isEmpty) return 'Enter the primary passenger name.';
  if (trimmed.length < 2) return 'Name looks too short.';
  return null;
}

String? validatePassengerPhone(String? v) {
  final trimmed = (v ?? '').trim();
  if (trimmed.isEmpty) return 'Enter a mobile number.';
  if (trimmed == _blockedDefaultPhone) return 'Enter your real mobile number.';
  if (!_indianMobileRe.hasMatch(trimmed)) return 'Enter a valid 10-digit Indian mobile.';
  return null;
}

class TicketingNotifier extends StateNotifier<TicketingState> {
  final TicketingService _service;

  TicketingNotifier(this._service) : super(const TicketingState());

  void setStations(MetroStation origin, MetroStation destination) {
    state = state.copyWith(
      originStation: origin,
      destinationStation: destination,
      status: BookingStatus.idle,
    );
  }

  void setPassengerCount(int count) {
    state = state.copyWith(passengerCount: count);
  }

  void setPassengerDetails(String name, String phone) {
    state = state.copyWith(passengerName: name.trim(), passengerPhone: phone.trim());
  }

  void selectOption(RouteOption option) {
    state = state.copyWith(selectedOption: option);
  }

  /// Called whenever the Firebase auth user changes. Any in-flight txn belongs
  /// to the previous user and must not be reused.
  void resetForAuthChange() {
    state = const TicketingState();
  }

  Future<void> searchRoutes() async {
    if (state.originStation == null || state.destinationStation == null) {
      state = state.copyWith(
        status: BookingStatus.error,
        errorMessage: 'Please select both origin and destination stations.',
      );
      return;
    }

    // Show the catalog immediately so the Route Selection screen is never
    // empty — but keep the transactionId slot blank until the backend confirms
    // a real one. Users can browse; checkout will wait for the server txn.
    state = state.copyWith(
      status: BookingStatus.searching,
      availableOptions: _defaultRouteCatalog,
      selectedOption: _defaultRouteCatalog.first,
      transactionId: null,
      clearError: true,
    );

    final err = await _ensureServerTransaction();
    state = state.copyWith(
      status: BookingStatus.routesLoaded,
      errorMessage: err,
    );
  }

  /// Ensure we have a backend-registered transaction id. Idempotent: safe to
  /// call multiple times. Sets `state.transactionId` on success; surfaces the
  /// underlying error so checkout doesn't get a generic "reach the network"
  /// message when the cause is auth or a specific HTTP failure.
  Future<String?> _ensureServerTransaction() async {
    if (state.transactionId != null && state.transactionId!.isNotEmpty) {
      return null;
    }
    if (state.originStation == null || state.destinationStation == null) {
      return 'Pick origin and destination first.';
    }

    try {
      final res = await _service.searchRoutes(
        originStationId: state.originStation!.code ?? state.originStation!.id,
        destinationStationId: state.destinationStation!.code ?? state.destinationStation!.id,
      );
      final serverTxn = res['transaction_id'] as String?;
      if (serverTxn != null && serverTxn.isNotEmpty) {
        state = state.copyWith(transactionId: serverTxn);
        return null;
      }
      return 'Search response did not include a transaction id.';
    } on TicketingAuthRequiredException {
      return 'Please sign in again to continue booking.';
    } on TicketingApiException catch (e) {
      return 'Search failed (HTTP ${e.statusCode}): ${e.message}';
    } catch (e) {
      if (kDebugMode) debugPrint('_ensureServerTransaction failed: $e');
      return 'Search failed: $e';
    }
  }

  /// Prepares the booking up to the Razorpay checkout screen. Runs select+init,
  /// then asks the backend to create a Razorpay order (which owns the amount).
  /// Returns a [RazorpayCheckout] the UI can hand to the Razorpay SDK, or null
  /// on error (error surfaced via state).
  ///
  /// Unreserved SJT/RJT tickets don't require the user to input passenger
  /// details — [autoName]/[autoPhone] come from the signed-in Firebase profile
  /// and satisfy the ONDC billing block. Callers pass whatever they have; we
  /// fill sensible defaults.
  Future<RazorpayCheckout?> prepareRazorpayCheckout({
    required String autoName,
    required String autoPhone,
    String? autoEmail,
    String? promoCode,
  }) async {
    if (state.selectedOption == null) {
      state = state.copyWith(
        status: BookingStatus.error,
        errorMessage: 'Please pick a ticket type first.',
      );
      return null;
    }

    state = state.copyWith(
      status: BookingStatus.bookingInInit,
      passengerName: autoName,
      passengerPhone: autoPhone,
      clearError: true,
      clearCheckout: true,
    );

    // Retry search if we don't have a server txn yet.
    final searchErr = await _ensureServerTransaction();
    if (state.transactionId == null) {
      state = state.copyWith(
        status: BookingStatus.error,
        errorMessage: searchErr ?? 'Could not reach the metro network.',
      );
      return null;
    }

    try {
      final txnId = state.transactionId!;
      final option = state.selectedOption!;

      await _service.selectTicket(
        transactionId: txnId,
        itemId: option.id,
        passengerCount: state.passengerCount,
        promoCode: promoCode,
      );

      await _service.initTicket(
        transactionId: txnId,
        itemId: option.id,
        passengerName: autoName,
        passengerPhone: autoPhone,
        passengerEmail: autoEmail,
        passengerCount: state.passengerCount,
      );

      final order = await _service.createRazorpayOrder(
        transactionId: txnId,
        itemId: option.id,
        passengerCount: state.passengerCount,
      );

      final rzp = RazorpayCheckout(
        razorpayKeyId: order['key_id'] as String,
        razorpayOrderId: order['order_id'] as String,
        amountInPaise: (order['amount'] as num).toInt(),
        currency: (order['currency'] as String?) ?? 'INR',
        prefillName: autoName,
        prefillPhone: autoPhone,
        prefillEmail: autoEmail,
      );

      state = state.copyWith(status: BookingStatus.paymentPending, pendingCheckout: rzp);
      return rzp;
    } on TicketingAuthRequiredException catch (e) {
      state = state.copyWith(status: BookingStatus.error, errorMessage: e.toString());
      return null;
    } on TicketingApiException catch (e) {
      state = state.copyWith(status: BookingStatus.error, errorMessage: e.message);
      return null;
    } catch (e) {
      if (kDebugMode) debugPrint('prepareRazorpayCheckout error: $e');
      state = state.copyWith(
        status: BookingStatus.error,
        errorMessage: 'Unable to start payment. Please try again.',
      );
      return null;
    }
  }

  /// Called by the UI after Razorpay SDK returns success. Server verifies the
  /// signature and only then issues a signed MetroTicket.
  Future<bool> completePaymentAndConfirm({
    required String razorpayOrderId,
    required String razorpayPaymentId,
    required String razorpaySignature,
  }) async {
    if (state.transactionId == null || state.selectedOption == null) return false;
    state = state.copyWith(status: BookingStatus.paymentVerifying, clearError: true);

    try {
      final ticket = await _service.confirmPayment(
        transactionId: state.transactionId!,
        razorpayOrderId: razorpayOrderId,
        razorpayPaymentId: razorpayPaymentId,
        razorpaySignature: razorpaySignature,
        itemId: state.selectedOption!.id,
        passengerCount: state.passengerCount,
      );
      state = state.copyWith(
        status: BookingStatus.ticketConfirmed,
        activeTicket: ticket,
        clearCheckout: true,
      );
      return true;
    } on TicketingAuthRequiredException catch (e) {
      state = state.copyWith(status: BookingStatus.error, errorMessage: e.toString());
      return false;
    } on TicketingApiException catch (e) {
      state = state.copyWith(status: BookingStatus.error, errorMessage: e.message);
      return false;
    } catch (e) {
      if (kDebugMode) debugPrint('confirmPayment error: $e');
      state = state.copyWith(
        status: BookingStatus.error,
        errorMessage: 'Payment verification failed. If money was deducted it will auto-refund.',
      );
      return false;
    }
  }

  void reportPaymentCancelled() {
    state = state.copyWith(
      status: BookingStatus.routesLoaded,
      errorMessage: 'Payment cancelled.',
      clearCheckout: true,
    );
  }

  void reportPaymentFailed(String? reason) {
    state = state.copyWith(
      status: BookingStatus.error,
      errorMessage: reason?.isNotEmpty == true ? reason! : 'Payment failed.',
      clearCheckout: true,
    );
  }
}

final ticketingNotifierProvider = StateNotifierProvider<TicketingNotifier, TicketingState>((ref) {
  final service = ref.watch(ticketingServiceProvider);
  return TicketingNotifier(service);
});

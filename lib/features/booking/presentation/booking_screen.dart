// lib/features/booking/presentation/booking_screen.dart
//
// Single-screen metro ticket booking. Collapses what used to be three screens
// (Where to? → Select Route & Ticket → Checkout) into one, Rapido-style:
// pick stations, pick ticket type + passengers, apply a promo, and pay — all
// here. The Razorpay sheet and the post-payment confirmation timeline
// (BookingProgressView) follow as before.

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

import '../../../design_system/tokens/colors.dart';
import '../../../design_system/tokens/radius.dart';
import '../../../design_system/tokens/spacing.dart';
import '../../../design_system/tokens/typography.dart';
import '../../../models/metro_station.dart';
import '../../../services/location_service.dart';
import '../../promo/promo_banner.dart';
import '../application/ticketing_provider.dart';
import 'booking_progress_view.dart';

class BookingScreen extends ConsumerStatefulWidget {
  const BookingScreen({super.key});

  @override
  ConsumerState<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends ConsumerState<BookingScreen> {
  late final Razorpay _razorpay;
  final _promoController = TextEditingController();
  bool _promoExpanded = false;

  MetroStation? _origin;
  MetroStation? _destination;
  late List<MetroStation> _ranked = List.of(_stations);
  bool _locating = false;
  bool _autoDetected = false;

  // `line:` is the human label shown in the UI; the model derives lineIds from
  // it. Codes double as the station identifiers sent to the backend search.
  static final List<MetroStation> _stations = [
    MetroStation(id: 'hyd_red_01', code: 'MYP', name: 'Miyapur', line: 'Red Line', distance: 0, latitude: 17.4959, longitude: 78.3612),
    MetroStation(id: 'hyd_red_03', code: 'JNTU', name: 'JNTU College', line: 'Red Line', distance: 0, latitude: 17.4923, longitude: 78.3862),
    MetroStation(id: 'hyd_red_04', code: 'KPHB', name: 'KPHB Colony', line: 'Red Line', distance: 0, latitude: 17.4849, longitude: 78.3915),
    MetroStation(id: 'hyd_red_11', code: 'AMP', name: 'Ameerpet', line: 'Red & Blue Lines', distance: 0, latitude: 17.4374, longitude: 78.4482),
    MetroStation(id: 'hyd_red_18', code: 'MGBS', name: 'MG Bus Station', line: 'Red & Green Lines', distance: 0, latitude: 17.3782, longitude: 78.4867),
    MetroStation(id: 'hyd_red_27', code: 'LBN', name: 'LB Nagar', line: 'Red Line', distance: 0, latitude: 17.3479, longitude: 78.5525),
    MetroStation(id: 'hyd_blue_01', code: 'NGL', name: 'Nagole', line: 'Blue Line', distance: 0, latitude: 17.3820, longitude: 78.5583),
    MetroStation(id: 'hyd_blue_15', code: 'HTC', name: 'Hitec City', line: 'Blue Line', distance: 0, latitude: 17.4483, longitude: 78.3782),
    MetroStation(id: 'hyd_blue_16', code: 'RDG', name: 'Raidurg', line: 'Blue Line', distance: 0, latitude: 17.4413, longitude: 78.3792),
    MetroStation(id: 'hyd_green_01', code: 'JBS', name: 'Jubilee Bus Station', line: 'Green Line', distance: 0, latitude: 17.4437, longitude: 78.4956),
  ];

  @override
  void initState() {
    super.initState();
    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _onPaymentSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _onPaymentError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _onExternalWallet);
    _origin = _stations.firstWhere((s) => s.code == 'MYP');
    _destination = _stations.firstWhere((s) => s.code == 'LBN');
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _detectNearest();
      _syncStationsAndSearch();
    });
  }

  @override
  void dispose() {
    _promoController.dispose();
    _razorpay.clear();
    super.dispose();
  }

  // ── Station selection ──────────────────────────────────────────────────────

  Future<void> _detectNearest() async {
    setState(() => _locating = true);
    try {
      final pos = await LocationService().getCurrentLocation();
      final ranked = _stations.map((s) {
        final km = Geolocator.distanceBetween(pos.latitude, pos.longitude, s.latitude, s.longitude) / 1000;
        return s.copyWith(distance: double.parse(km.toStringAsFixed(1)));
      }).toList()
        ..sort((a, b) => a.distance.compareTo(b.distance));
      if (!mounted) return;
      final nearest = ranked.first;
      // Keep the current destination if it's still valid; otherwise default to a
      // sensible far terminus so the trip isn't a trivial one-stop hop.
      var dest = _destination;
      if (dest == null || dest.id == nearest.id) {
        dest = ranked.lastWhere((s) => s.id != nearest.id, orElse: () => ranked.last);
      }
      setState(() {
        _ranked = ranked;
        _origin = nearest;
        _destination = dest;
        _autoDetected = true;
      });
    } catch (e) {
      if (kDebugMode) debugPrint('Nearest-station detect failed: $e');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  /// Push the chosen stations into the provider and (re)fetch the server
  /// transaction so checkout is ready by the time the user taps Pay.
  void _syncStationsAndSearch() {
    if (_origin == null || _destination == null || _origin!.id == _destination!.id) return;
    final n = ref.read(ticketingNotifierProvider.notifier);
    n.setStations(_origin!, _destination!);
    n.searchRoutes();
  }

  void _swap() {
    setState(() {
      final t = _origin;
      _origin = _destination;
      _destination = t;
    });
    _syncStationsAndSearch();
  }

  Future<void> _pickStation({required bool origin}) async {
    final excluded = origin ? _destination?.id : _origin?.id;
    final selected = await showModalBottomSheet<MetroStation>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.borderRadiusXL),
      builder: (ctx) => _StationPickerSheet(
        title: origin ? 'Select origin' : 'Select destination',
        stations: _ranked.where((s) => s.id != excluded).toList(),
        lineColor: _lineColor,
      ),
    );
    if (selected == null || !mounted) return;
    setState(() {
      if (origin) {
        _origin = selected;
      } else {
        _destination = selected;
      }
    });
    _syncStationsAndSearch();
  }

  Color _lineColor(String line) {
    if (line.contains('Red')) return Colors.redAccent;
    if (line.contains('Blue')) return Colors.blueAccent;
    if (line.contains('Green')) return Colors.green;
    return AppColors.primary;
  }

  // ── Payment ────────────────────────────────────────────────────────────────

  ({String name, String phone, String? email}) _autoFillFromFirebase() {
    final user = FirebaseAuth.instance.currentUser;
    final displayName = user?.displayName?.trim();
    final name = (displayName != null && displayName.isNotEmpty) ? displayName : 'MetroSafar Passenger';
    // Only a REAL phone is passed as contact — a placeholder would just make
    // Razorpay show its "Contact details" screen anyway. With a real phone +
    // email prefilled, Razorpay skips that screen entirely.
    final phone = (user?.phoneNumber != null && user!.phoneNumber!.trim().length >= 10)
        ? user.phoneNumber!.trim()
        : '';
    return (name: name, phone: phone, email: user?.email);
  }

  Future<void> _startCheckout() async {
    final auto = _autoFillFromFirebase();
    final promo = _promoController.text.trim();
    final checkout = await ref.read(ticketingNotifierProvider.notifier).prepareRazorpayCheckout(
          autoName: auto.name,
          autoPhone: auto.phone.isEmpty ? '+91-9999999999' : auto.phone,
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
        if (auto.phone.isNotEmpty) 'contact': auto.phone,
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

  // ── UI ───────────────────────────────────────────────────────────────────

  bool get _canProceed => _origin != null && _destination != null && _origin!.id != _destination!.id;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final state = ref.watch(ticketingNotifierProvider);
    final option = state.selectedOption;
    final total = (option?.fare ?? 0) * state.passengerCount;

    // After Razorpay returns success we're in the two-phase confirmation — show
    // the timeline (or refund) instead of the form.
    if (state.status == BookingStatus.paymentVerifying ||
        state.status == BookingStatus.refundInitiated) {
      return Scaffold(
        appBar: AppBar(automaticallyImplyLeading: false),
        body: BookingProgressView(
          status: state.status,
          fromStation: _origin?.name ?? '—',
          toStation: _destination?.name ?? '—',
          fareLabel: '₹${total.toStringAsFixed(0)}',
          refundReference: state.refundReference,
          onDone: () => context.go('/home'),
        ),
      );
    }

    final busy = state.status == BookingStatus.bookingInInit ||
        state.status == BookingStatus.paymentPending;

    return Scaffold(
      appBar: AppBar(title: Text('Book a ticket', style: AppTypography.headlineMedium)),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(AppSpacing.s4),
                children: [
                  // ── From / To ──
                  Container(
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHigh,
                      borderRadius: AppRadius.borderRadiusL,
                    ),
                    child: Column(
                      children: [
                        _StationRow(
                          icon: Icons.my_location_rounded,
                          iconColor: Colors.green,
                          label: 'From',
                          station: _origin,
                          hint: _autoDetected ? 'Nearest station' : 'Pick origin',
                          onTap: () => _pickStation(origin: true),
                        ),
                        Divider(height: 1, color: cs.outlineVariant),
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 2),
                            child: IconButton.filledTonal(
                              onPressed: _swap,
                              icon: const Icon(Icons.swap_vert_rounded),
                              tooltip: 'Swap',
                            ),
                          ),
                        ),
                        Divider(height: 1, color: cs.outlineVariant),
                        _StationRow(
                          icon: Icons.location_on_rounded,
                          iconColor: Colors.redAccent,
                          label: 'To',
                          station: _destination,
                          hint: 'Pick destination',
                          onTap: () => _pickStation(origin: false),
                        ),
                      ],
                    ),
                  ),

                  // Route ETA line (folded in from the old route screen).
                  if (_canProceed) ...[
                    const SizedBox(height: AppSpacing.s3),
                    Row(
                      children: [
                        Icon(Icons.directions_subway_filled_rounded,
                            size: 18, color: AppColors.electricTeal),
                        const SizedBox(width: AppSpacing.s2),
                        Text(
                          '${option?.totalStops ?? 8} stops · Est. ${option?.totalDurationMinutes ?? 24} min',
                          style: AppTypography.bodySmall.copyWith(color: cs.onSurfaceVariant),
                        ),
                        if (_locating) ...[
                          const SizedBox(width: AppSpacing.s3),
                          const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
                        ],
                      ],
                    ),
                  ],

                  const SizedBox(height: AppSpacing.s5),

                  // ── Ticket type toggle (SJT / RJT) ──
                  Text('Ticket', style: AppTypography.titleMedium.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: AppSpacing.s3),
                  ...state.availableOptions.map((o) {
                    final selected = state.selectedOption?.id == o.id;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.s3),
                      child: InkWell(
                        onTap: () => ref.read(ticketingNotifierProvider.notifier).selectOption(o),
                        borderRadius: AppRadius.borderRadiusL,
                        child: Container(
                          padding: const EdgeInsets.all(AppSpacing.s4),
                          decoration: BoxDecoration(
                            borderRadius: AppRadius.borderRadiusL,
                            border: Border.all(
                              color: selected ? AppColors.primary : cs.outlineVariant.withValues(alpha: 0.4),
                              width: selected ? 2 : 1,
                            ),
                            color: selected ? AppColors.primary.withValues(alpha: 0.05) : null,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                                color: selected ? AppColors.primary : cs.onSurfaceVariant,
                                size: 22,
                              ),
                              const SizedBox(width: AppSpacing.s3),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(o.title, style: AppTypography.titleMedium),
                                    const SizedBox(height: 2),
                                    Text(
                                      o.type == 'SJT'
                                          ? 'Single entry & exit today'
                                          : 'Return within 24 hrs',
                                      style: AppTypography.bodySmall.copyWith(color: cs.onSurfaceVariant),
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                '₹${o.fare.toStringAsFixed(0)}',
                                style: AppTypography.titleMedium.copyWith(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  }),

                  const SizedBox(height: AppSpacing.s2),

                  // ── Passengers ──
                  Row(
                    children: [
                      Text('Passengers', style: AppTypography.titleMedium),
                      const Spacer(),
                      _PaxStepper(
                        value: state.passengerCount,
                        onChanged: (v) => ref.read(ticketingNotifierProvider.notifier).setPassengerCount(v),
                      ),
                    ],
                  ),

                  const Divider(height: AppSpacing.s6),

                  // ── Promo ──
                  InkWell(
                    onTap: () => setState(() => _promoExpanded = !_promoExpanded),
                    borderRadius: AppRadius.borderRadiusM,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s2),
                      child: Row(
                        children: [
                          Icon(Icons.local_offer_outlined, size: 18, color: cs.onSurfaceVariant),
                          const SizedBox(width: 8),
                          Text(
                            _promoController.text.isEmpty
                                ? 'Have a promo code?'
                                : 'Promo: ${_promoController.text.toUpperCase()}',
                            style: AppTypography.bodyMedium.copyWith(color: AppColors.primary),
                          ),
                          const Spacer(),
                          Icon(_promoExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                              color: cs.onSurfaceVariant),
                        ],
                      ),
                    ),
                  ),
                  if (_promoExpanded)
                    Padding(
                      padding: const EdgeInsets.only(top: AppSpacing.s2),
                      child: TextField(
                        controller: _promoController,
                        textCapitalization: TextCapitalization.characters,
                        decoration: InputDecoration(
                          hintText: 'e.g. METRO20',
                          border: OutlineInputBorder(borderRadius: AppRadius.borderRadiusM),
                          isDense: true,
                        ),
                        onChanged: (_) => setState(() {}),
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
                          Expanded(child: Text(state.errorMessage!, style: const TextStyle(color: Colors.red))),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: AppSpacing.s4),
                  const SlotBanner(slot: 'booking_top'),
                ],
              ),
            ),

            // ── Pinned pay bar ──
            Container(
              padding: const EdgeInsets.all(AppSpacing.s4),
              decoration: BoxDecoration(
                color: cs.surface,
                border: Border(top: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5))),
              ),
              child: Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Total', style: AppTypography.bodySmall.copyWith(color: cs.onSurfaceVariant)),
                      Text('₹${total.toStringAsFixed(0)}',
                          style: AppTypography.headlineMedium.copyWith(
                              color: AppColors.primary, fontWeight: FontWeight.w800)),
                    ],
                  ),
                  const SizedBox(width: AppSpacing.s4),
                  Expanded(
                    child: SizedBox(
                      height: 52,
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: AppRadius.borderRadiusL),
                        ),
                        onPressed: (!_canProceed || busy || option == null) ? null : _startCheckout,
                        child: busy
                            ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                            : Text('Pay ₹${total.toStringAsFixed(0)} & Book',
                                style: AppTypography.titleMedium.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Reusable bits (relocated from the retired station/route screens) ─────────

class _StationRow extends StatelessWidget {
  const _StationRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.station,
    required this.hint,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final MetroStation? station;
  final String hint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.borderRadiusL,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s4),
        child: Row(
          children: [
            Icon(icon, color: iconColor, size: 24),
            const SizedBox(width: AppSpacing.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: AppTypography.bodySmall.copyWith(color: cs.onSurfaceVariant)),
                  const SizedBox(height: 2),
                  Text(
                    station?.name ?? hint,
                    style: AppTypography.titleMedium.copyWith(
                      fontWeight: FontWeight.w700,
                      color: station != null ? cs.onSurface : cs.outline,
                    ),
                  ),
                  if (station != null)
                    Text(
                      station!.distance > 0
                          ? '${station!.line} · ${station!.distance.toStringAsFixed(1)} km away'
                          : station!.line,
                      style: AppTypography.bodySmall.copyWith(color: cs.onSurfaceVariant),
                    ),
                ],
              ),
            ),
            Icon(Icons.keyboard_arrow_down_rounded, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

class _PaxStepper extends StatelessWidget {
  const _PaxStepper({required this.value, required this.onChanged});
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton.filledTonal(
          onPressed: value > 1 ? () => onChanged(value - 1) : null,
          icon: const Icon(Icons.remove_rounded),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s3),
          child: Text('$value', style: AppTypography.titleLarge.copyWith(fontWeight: FontWeight.w700)),
        ),
        IconButton.filledTonal(
          onPressed: value < 6 ? () => onChanged(value + 1) : null,
          icon: const Icon(Icons.add_rounded),
        ),
      ],
    );
  }
}

class _StationPickerSheet extends StatefulWidget {
  const _StationPickerSheet({required this.title, required this.stations, required this.lineColor});
  final String title;
  final List<MetroStation> stations;
  final Color Function(String) lineColor;

  @override
  State<_StationPickerSheet> createState() => _StationPickerSheetState();
}

class _StationPickerSheetState extends State<_StationPickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.toLowerCase();
    final filtered = widget.stations.where((s) {
      return s.name.toLowerCase().contains(q) ||
          (s.code?.toLowerCase().contains(q) ?? false) ||
          s.line.toLowerCase().contains(q);
    }).toList();

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (ctx, scrollController) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.s4),
              child: Row(
                children: [
                  Expanded(child: Text(widget.title, style: AppTypography.headlineSmall)),
                  IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s4),
              child: TextField(
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  hintText: 'Search stations…',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(borderRadius: AppRadius.borderRadiusL, borderSide: BorderSide.none),
                  filled: true,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.s3),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s4),
                itemCount: filtered.length,
                itemBuilder: (context, i) {
                  final s = filtered[i];
                  final color = widget.lineColor(s.line);
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: color.withValues(alpha: 0.15),
                      child: Text(
                        s.code ?? s.name.substring(0, 2).toUpperCase(),
                        style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ),
                    title: Text(s.name, style: AppTypography.titleMedium),
                    subtitle: Text(
                      s.distance > 0 ? '${s.line} · ${s.distance.toStringAsFixed(1)} km' : s.line,
                      style: AppTypography.bodySmall,
                    ),
                    onTap: () => Navigator.pop(context, s),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

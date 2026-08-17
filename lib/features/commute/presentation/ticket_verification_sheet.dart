import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/commute/ride_verification.dart';
import '../../../design_system/tokens/colors.dart';
import '../../../design_system/tokens/radius.dart';
import '../../../design_system/tokens/spacing.dart';
import '../../../design_system/tokens/typography.dart';

Future<RideVerification?> showRideVerificationSheet(BuildContext context) {
  return showModalBottomSheet<RideVerification>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (context) => const _TicketVerificationSheet(),
  );
}

class _TicketVerificationSheet extends StatefulWidget {
  const _TicketVerificationSheet();

  @override
  State<_TicketVerificationSheet> createState() =>
      _TicketVerificationSheetState();
}

class _TicketVerificationSheetState extends State<_TicketVerificationSheet> {
  final _controller = TextEditingController();
  final _scannerController = MobileScannerController();
  String _method = 'qr';
  bool _showScanner = false;
  bool _handledScan = false;

  @override
  void dispose() {
    _controller.dispose();
    _scannerController.dispose();
    super.dispose();
  }

  void _submit() {
    final code = _controller.text.trim();
    if (_method != 'qr' || code.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Scan an official MetroSafar station QR code to start.',
          ),
        ),
      );
      return;
    }
    Navigator.of(context).pop(RideVerification(method: _method, code: code));
  }

  static const _kQrPrefix = 'metrosafar://verify/';

  void _handleScan(BarcodeCapture capture) {
    if (_handledScan) return;
    final rawValue = capture.barcodes
        .map((barcode) => barcode.rawValue)
        .whereType<String>()
        .firstWhere((value) => value.trim().isNotEmpty, orElse: () => '');
    if (rawValue.isEmpty) return;

    // Reject payloads that don't match the official MetroSafar URI scheme.
    // This prevents quishing attacks (malicious QR stickers at stations) and
    // ensures only our cryptographically signed tokens reach the backend.
    if (!rawValue.startsWith(_kQrPrefix)) {
      _handledScan = false; // allow a re-scan
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Invalid QR code — please scan an official MetroSafar station code.',
          ),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // Extract the HMAC token from the URI (everything after the prefix).
    final token = rawValue.substring(_kQrPrefix.length).trim();
    if (token.isEmpty) {
      _handledScan = false;
      return;
    }

    _handledScan = true;
    setState(() {
      _method = 'qr';
      _showScanner = false;
      _controller.text = token;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        margin: const EdgeInsets.all(AppSpacing.s3),
        padding: const EdgeInsets.all(AppSpacing.s5),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: AppRadius.borderRadiusXL,
          boxShadow: [
            BoxShadow(
              color: AppColors.cityInk.withValues(alpha: 0.18),
              blurRadius: 24,
              offset: const Offset(0, -8),
            ),
          ],
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppColors.neonLime.withValues(alpha: 0.2),
                      borderRadius: AppRadius.borderRadiusL,
                    ),
                    child: Icon(
                      Icons.qr_code_scanner_outlined,
                      color: AppColors.cityInk,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s3),
                  Expanded(
                    child: Text(
                      'Verify your ride',
                      style: AppTypography.titleLarge.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                    tooltip: 'Close',
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.s3),
              Text(
                'Scan the official MetroSafar QR at the station. Rewards start only after the backend verifies it.',
                style: AppTypography.bodyMedium.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.s4),
              if (_showScanner) ...[
                ClipRRect(
                  borderRadius: AppRadius.borderRadiusL,
                  child: SizedBox(
                    height: 260,
                    child: MobileScanner(
                      controller: _scannerController,
                      onDetect: _handleScan,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.s3),
              ],
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        setState(() {
                          _handledScan = false;
                          _showScanner = !_showScanner;
                        });
                      },
                      icon: Icon(
                        _showScanner
                            ? Icons.close
                            : Icons.qr_code_scanner_outlined,
                      ),
                      label: Text(
                        _showScanner ? 'Close scanner' : 'Scan station QR',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.s3),
              TextField(
                controller: _controller,
                readOnly: true,
                decoration: const InputDecoration(
                  labelText: 'Verified station token',
                  hintText: 'Scan the station QR above',
                  prefixIcon: Icon(Icons.qr_code_2_outlined),
                ),
              ),
              const SizedBox(height: AppSpacing.s4),
              FilledButton.icon(
                onPressed: _submit,
                icon: const Icon(Icons.verified_outlined),
                label: const Text('Start verified ride'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  backgroundColor: AppColors.neonLime,
                  foregroundColor: AppColors.cityInk,
                ),
              ),
              const SizedBox(height: AppSpacing.s2),
              Text(
                'The QR is checked by the backend and expires automatically. A screenshot or manually entered ticket number cannot activate rewards.',
                style: AppTypography.bodySmall.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

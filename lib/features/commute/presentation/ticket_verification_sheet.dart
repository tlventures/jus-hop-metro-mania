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
  String _method = 'manual';
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
    if (code.length < 6) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter or scan a valid ticket code to start.'),
        ),
      );
      return;
    }
    Navigator.of(context).pop(RideVerification(method: _method, code: code));
  }

  void _handleScan(BarcodeCapture capture) {
    if (_handledScan) return;
    final rawValue = capture.barcodes
        .map((barcode) => barcode.rawValue)
        .whereType<String>()
        .firstWhere((value) => value.trim().isNotEmpty, orElse: () => '');
    if (rawValue.isEmpty) return;
    _handledScan = true;
    setState(() {
      _method = 'qr';
      _showScanner = false;
      _controller.text = rawValue.trim();
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
                'Scan the QR/barcode on your metro ticket, or enter the ticket reference code. Rewards start only after verification.',
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
                            ? Icons.keyboard_outlined
                            : Icons.qr_code_scanner_outlined,
                      ),
                      label: Text(_showScanner ? 'Enter code' : 'Scan ticket'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.s3),
              TextField(
                controller: _controller,
                textInputAction: TextInputAction.done,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'Ticket or QR reference',
                  hintText: 'Example: 8F4K2A91',
                  prefixIcon: Icon(Icons.confirmation_number_outlined),
                ),
                onChanged: (_) => _method = 'manual',
                onSubmitted: (_) => _submit(),
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
                'MetroSafar uses this only to verify reward eligibility. The backend stores a protected token instead of the raw ticket code.',
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

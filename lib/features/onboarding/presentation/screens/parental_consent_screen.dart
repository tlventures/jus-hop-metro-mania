import 'package:flutter/material.dart';

import '../../../../design_system/tokens/radius.dart';
import '../../../../design_system/tokens/spacing.dart';
import '../../../../design_system/tokens/typography.dart';
import '../../../../services/backend_service.dart';

/// Shown when the user confirms they are under 18.
///
/// Collects a parent/guardian email address and requests a verification link
/// via the backend.  The under-18 user is allowed to proceed into a
/// **restricted** version of the app (ads and analytics disabled, GPS
/// polling off) while consent is pending — hard-blocking leads to abandonment.
///
/// Once the parent verifies via the email link, [MinorStatus.setParentVerified()]
/// is called and restrictions remain but are tracked as consented.
class ParentalConsentScreen extends StatefulWidget {
  final VoidCallback onContinue;
  final VoidCallback? onBack;

  const ParentalConsentScreen({
    required this.onContinue,
    this.onBack,
    super.key,
  });

  @override
  State<ParentalConsentScreen> createState() => _ParentalConsentScreenState();
}

class _ParentalConsentScreenState extends State<ParentalConsentScreen> {
  final _emailCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _sending = false;
  bool _sent = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _requestConsent() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() { _sending = true; _errorMessage = null; });

    try {
      await BackendService().requestParentalConsent(
        parentEmail: _emailCtrl.text.trim(),
      );
      if (mounted) { setState(() { _sending = false; _sent = true; }); }
    } catch (e) {
      if (mounted) {
        setState(() {
          _sending = false;
          _errorMessage = 'Could not send verification — check the email and try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.s6),
            child: _sent ? _buildSentState(colorScheme) : _buildForm(colorScheme),
          ),
        ),
      ),
    );
  }

  Widget _buildForm(ColorScheme cs) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.onBack != null)
            IconButton(icon: const Icon(Icons.arrow_back), onPressed: widget.onBack),
          const SizedBox(height: AppSpacing.s4),
          Container(
            padding: const EdgeInsets.all(AppSpacing.s4),
            decoration: BoxDecoration(
              color: cs.secondaryContainer,
              borderRadius: AppRadius.borderRadiusXL,
            ),
            child: Row(
              children: [
                Icon(Icons.shield_outlined, color: cs.onSecondaryContainer),
                const SizedBox(width: AppSpacing.s3),
                Expanded(
                  child: Text(
                    'Because you\'re under 18, a parent or guardian needs to give permission.',
                    style: AppTypography.bodySmall.copyWith(color: cs.onSecondaryContainer),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.s5),
          Text(
            'Parent or guardian email',
            style: AppTypography.headlineSmall.copyWith(
              color: cs.onSurface,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: AppSpacing.s2),
          Text(
            'We\'ll send a one-click verification link. No account needed.',
            style: AppTypography.bodyMedium.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.s5),
          TextFormField(
            controller: _emailCtrl,
            keyboardType: TextInputType.emailAddress,
            autofillHints: const [AutofillHints.email],
            decoration: InputDecoration(
              hintText: 'parent@example.com',
              prefixIcon: const Icon(Icons.email_outlined),
              border: OutlineInputBorder(borderRadius: AppRadius.borderRadiusL),
            ),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Please enter an email address';
              if (!RegExp(r'^[\w.+-]+@[\w-]+\.\w{2,}$').hasMatch(v.trim())) {
                return 'Enter a valid email address';
              }
              return null;
            },
          ),
          if (_errorMessage != null) ...[
            const SizedBox(height: AppSpacing.s3),
            Text(_errorMessage!, style: AppTypography.bodySmall.copyWith(color: cs.error)),
          ],
          const Spacer(),
          // The under-18 user may proceed into a restricted app immediately;
          // they don't have to wait for parent verification.
          Text(
            'You can use MetroSafar while waiting for verification. Ads and tracking will stay off.',
            style: AppTypography.bodySmall.copyWith(color: cs.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.s4),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _sending ? null : _requestConsent,
              child: _sending
                  ? const SizedBox(width: 22, height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Send verification link'),
            ),
          ),
          const SizedBox(height: AppSpacing.s3),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: widget.onContinue,
              child: const Text('Continue without parent email'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSentState(ColorScheme cs) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(Icons.mark_email_read_outlined, size: 72, color: cs.primary),
        const SizedBox(height: AppSpacing.s5),
        Text(
          'Verification email sent!',
          style: AppTypography.headlineSmall.copyWith(
            color: cs.onSurface,
            fontWeight: FontWeight.w800,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.s3),
        Text(
          'Ask your parent to check their inbox and tap the link. You can start using MetroSafar now — ads are off for your account.',
          style: AppTypography.bodyMedium.copyWith(color: cs.onSurfaceVariant),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.s8),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: widget.onContinue,
            child: const Text('Start using MetroSafar'),
          ),
        ),
      ],
    );
  }
}

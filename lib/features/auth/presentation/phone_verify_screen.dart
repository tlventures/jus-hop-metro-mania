import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:metrosafar/design_system/tokens/spacing.dart';
import 'package:metrosafar/design_system/tokens/typography.dart';
import 'package:metrosafar/services/auth_service.dart';
import 'package:metrosafar/services/backend_service.dart';

/// Links a phone number (India, +91) to the signed-in account via Firebase
/// Phone Auth OTP. Earning endpoints are server-gated on the verified
/// phone_number token claim, so this is the unlock step for points.
///
/// On Android, instant verification / SMS auto-retrieval can complete the
/// link with no typing at all.
class PhoneVerifyScreen extends StatefulWidget {
  const PhoneVerifyScreen({super.key});

  @override
  State<PhoneVerifyScreen> createState() => _PhoneVerifyScreenState();
}

class _PhoneVerifyScreenState extends State<PhoneVerifyScreen> {
  final _authService = AuthService();
  final _phoneCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();

  bool _loading = false;
  bool _codeSent = false;
  String? _verificationId;
  int? _resendToken;
  String? _errorMessage;
  int _resendCooldown = 0;
  Timer? _cooldownTimer;

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _phoneCtrl.dispose();
    _otpCtrl.dispose();
    super.dispose();
  }

  String get _phoneE164 => '+91${_phoneCtrl.text.trim()}';

  bool get _phoneInputValid =>
      RegExp(r'^[6-9]\d{9}$').hasMatch(_phoneCtrl.text.trim());

  void _startCooldown() {
    _cooldownTimer?.cancel();
    setState(() => _resendCooldown = 30);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return timer.cancel();
      setState(() => _resendCooldown -= 1);
      if (_resendCooldown <= 0) timer.cancel();
    });
  }

  Future<void> _sendCode({bool resend = false}) async {
    if (!_phoneInputValid) {
      setState(() => _errorMessage = 'Please enter a valid 10-digit mobile number.');
      return;
    }
    setState(() { _loading = true; _errorMessage = null; });
    try {
      await _authService.startPhoneVerification(
        phoneE164: _phoneE164,
        resendToken: resend ? _resendToken : null,
        onCodeSent: (verificationId, resendToken) {
          if (!mounted) return;
          setState(() {
            _loading = false;
            _codeSent = true;
            _verificationId = verificationId;
            _resendToken = resendToken;
          });
          _startCooldown();
        },
        onFailed: (message) {
          if (!mounted) return;
          setState(() { _loading = false; _errorMessage = message; });
        },
        onVerified: _onVerified,
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _errorMessage = _authService.friendlyPhoneError(e);
        });
      }
    }
  }

  Future<void> _confirmCode() async {
    final code = _otpCtrl.text.trim();
    final verificationId = _verificationId;
    if (code.length != 6 || verificationId == null) {
      setState(() => _errorMessage = 'Enter the 6-digit code from the SMS.');
      return;
    }
    setState(() { _loading = true; _errorMessage = null; });
    try {
      await _authService.confirmSmsCode(verificationId, code);
      await _onVerified();
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _errorMessage = _authService.friendlyPhoneError(e);
        });
      }
    }
  }

  Future<void> _onVerified() async {
    // Stamp the user doc server-side. Best-effort: enforcement reads the
    // token claim, so a transient failure here doesn't block earning.
    try {
      await BackendService().confirmPhoneVerified();
    } catch (_) {}
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Phone verified — you can now earn points!'),
        behavior: SnackBarBehavior.floating,
      ),
    );
    context.go('/home');
  }

  void _skip() => context.go('/home');

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Verify your number'),
        actions: [
          TextButton(onPressed: _loading ? null : _skip, child: const Text('Skip for now')),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s6),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: AppSpacing.s6),
                  Icon(Icons.verified_user_outlined, size: 56, color: colorScheme.primary),
                  const SizedBox(height: AppSpacing.s4),
                  Text(
                    _codeSent ? 'Enter the code' : 'One quick step to start earning',
                    textAlign: TextAlign.center,
                    style: AppTypography.headlineSmall.copyWith(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s2),
                  Text(
                    _codeSent
                        ? 'We sent a 6-digit code to $_phoneE164.'
                        : 'Verifying your mobile number keeps rewards fair for everyone. One number, one account.',
                    textAlign: TextAlign.center,
                    style: AppTypography.bodyMedium.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s6),
                  if (_errorMessage != null) ...[
                    Container(
                      padding: const EdgeInsets.all(AppSpacing.s4),
                      decoration: BoxDecoration(
                        color: colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _errorMessage!,
                        style: AppTypography.bodySmall.copyWith(
                          color: colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.s4),
                  ],
                  if (!_codeSent) ...[
                    TextField(
                      controller: _phoneCtrl,
                      keyboardType: TextInputType.phone,
                      maxLength: 10,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      onChanged: (_) => setState(() => _errorMessage = null),
                      decoration: const InputDecoration(
                        hintText: '10-digit mobile number',
                        prefixText: '+91 ',
                        counterText: '',
                        prefixIcon: Icon(Icons.phone_android),
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.s4),
                    FilledButton(
                      onPressed: _loading || !_phoneInputValid ? null : _sendCode,
                      child: _loading
                          ? const SizedBox(
                              height: 20, width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('Send code'),
                    ),
                  ] else ...[
                    TextField(
                      controller: _otpCtrl,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      autofocus: true,
                      textAlign: TextAlign.center,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      onChanged: (_) => setState(() => _errorMessage = null),
                      style: AppTypography.headlineSmall.copyWith(letterSpacing: 8),
                      decoration: const InputDecoration(
                        hintText: '••••••',
                        counterText: '',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.s4),
                    FilledButton(
                      onPressed: _loading ? null : _confirmCode,
                      child: _loading
                          ? const SizedBox(
                              height: 20, width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('Verify'),
                    ),
                    TextButton(
                      onPressed: _loading || _resendCooldown > 0
                          ? null
                          : () => _sendCode(resend: true),
                      child: Text(
                        _resendCooldown > 0
                            ? 'Resend code in ${_resendCooldown}s'
                            : 'Resend code',
                      ),
                    ),
                    TextButton(
                      onPressed: _loading
                          ? null
                          : () => setState(() {
                                _codeSent = false;
                                _otpCtrl.clear();
                                _errorMessage = null;
                              }),
                      child: const Text('Change number'),
                    ),
                  ],
                  const SizedBox(height: AppSpacing.s6),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

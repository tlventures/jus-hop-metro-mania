import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:metrosafar/design_system/components/brand_logo.dart';
import 'package:metrosafar/design_system/tokens/spacing.dart';
import 'package:metrosafar/design_system/tokens/typography.dart';
import '../../../services/auth_service.dart';

/// Phone-number + OTP sign-in. India-first: defaults to +91 and a 10-digit
/// mobile number, the auth method most Hyderabad/Delhi/Bangalore/Chennai
/// commuters expect. Two phases in one screen: enter number → enter OTP.
class PhoneAuthScreen extends StatefulWidget {
  const PhoneAuthScreen({super.key});

  @override
  State<PhoneAuthScreen> createState() => _PhoneAuthScreenState();
}

class _PhoneAuthScreenState extends State<PhoneAuthScreen> {
  final _authService = AuthService();
  final _countryCodeCtrl = TextEditingController(text: '+91');
  final _phoneCtrl = TextEditingController();
  final _otpCtrl = TextEditingController();

  bool _codeSent = false;
  bool _loading = false;
  String? _error;
  String? _verificationId;
  int? _resendToken;

  Timer? _resendTimer;
  int _resendSeconds = 0;

  @override
  void dispose() {
    _resendTimer?.cancel();
    _countryCodeCtrl.dispose();
    _phoneCtrl.dispose();
    _otpCtrl.dispose();
    super.dispose();
  }

  String get _fullPhoneNumber {
    final code = _countryCodeCtrl.text.trim();
    final digits = _phoneCtrl.text.replaceAll(RegExp(r'\D'), '');
    return '$code$digits';
  }

  bool get _isPhoneValid {
    final digits = _phoneCtrl.text.replaceAll(RegExp(r'\D'), '');
    // 10 digits for India; allow 7–15 generally for other country codes.
    return digits.length >= 7 && digits.length <= 15;
  }

  Future<void> _sendOtp({bool resend = false}) async {
    FocusScope.of(context).unfocus();
    if (!_isPhoneValid) {
      setState(() => _error = 'Enter a valid mobile number.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _authService.verifyPhone(
        phoneNumber: _fullPhoneNumber,
        forceResendingToken: resend ? _resendToken : null,
        verificationCompleted: (credential) async {
          // Android instant verification / auto-retrieval — sign in silently.
          try {
            await _authService.signInWithPhoneCredential(credential);
            if (mounted) context.go('/home');
          } catch (_) {
            // Fall back to manual entry if silent sign-in fails.
          }
        },
        verificationFailed: (e) {
          if (mounted) {
            setState(() {
              _loading = false;
              _error = _friendlyError(e.code);
            });
          }
        },
        codeSent: (verificationId, resendToken) {
          if (!mounted) return;
          setState(() {
            _loading = false;
            _codeSent = true;
            _verificationId = verificationId;
            _resendToken = resendToken;
          });
          _startResendCooldown();
        },
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Could not send the code. Please try again.';
        });
      }
    }
  }

  Future<void> _verifyOtp() async {
    FocusScope.of(context).unfocus();
    final code = _otpCtrl.text.trim();
    if (code.length < 6 || _verificationId == null) {
      setState(() => _error = 'Enter the 6-digit code from the SMS.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await _authService.signInWithSmsCode(
        verificationId: _verificationId!,
        smsCode: code,
      );
      if (mounted) context.go('/home');
    } on FirebaseAuthException catch (e) {
      if (mounted) setState(() => _error = _friendlyError(e.code));
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Something went wrong. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _startResendCooldown() {
    _resendTimer?.cancel();
    setState(() => _resendSeconds = 30);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        _resendSeconds--;
        if (_resendSeconds <= 0) t.cancel();
      });
    });
  }

  void _changeNumber() {
    _resendTimer?.cancel();
    setState(() {
      _codeSent = false;
      _error = null;
      _otpCtrl.clear();
      _verificationId = null;
    });
  }

  String _friendlyError(String code) {
    switch (code) {
      case 'invalid-phone-number':
        return 'That phone number looks invalid.';
      case 'invalid-verification-code':
        return 'Incorrect code. Check the SMS and try again.';
      case 'session-expired':
      case 'code-expired':
        return 'The code expired. Tap Resend to get a new one.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';
      case 'quota-exceeded':
        return 'SMS limit reached. Please try again later.';
      case 'network-request-failed':
        return 'No internet connection.';
      case 'missing-client-identifier':
      case 'app-not-authorized':
        return 'Verification is temporarily unavailable. Try email sign-in.';
      default:
        return 'Something went wrong. Please try again.';
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: BackButton(onPressed: () => context.pop()),
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
                  const SizedBox(height: AppSpacing.s4),
                  const Center(child: MetroSafarLogo(size: 72)),
                  const SizedBox(height: AppSpacing.s5),
                  Text(
                    _codeSent ? 'Verify your number' : 'Sign in with phone',
                    textAlign: TextAlign.center,
                    style: AppTypography.headlineMedium.copyWith(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s2),
                  Text(
                    _codeSent
                        ? 'Enter the 6-digit code sent to $_fullPhoneNumber'
                        : "We'll text you a one-time code to confirm it's you.",
                    textAlign: TextAlign.center,
                    style: AppTypography.bodyMedium.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s7),

                  if (_error != null) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(AppSpacing.s4),
                      decoration: BoxDecoration(
                        color: colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _error!,
                        style: AppTypography.bodySmall.copyWith(
                          color: colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.s4),
                  ],

                  if (!_codeSent) ..._phoneStep(colorScheme) else ..._otpStep(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _phoneStep(ColorScheme colorScheme) {
    return [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 84,
            child: TextField(
              controller: _countryCodeCtrl,
              keyboardType: TextInputType.phone,
              textAlign: TextAlign.center,
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[+\d]')),
                LengthLimitingTextInputFormatter(4),
              ],
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: AppSpacing.s3,
                  vertical: AppSpacing.s5,
                ),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.s3),
          Expanded(
            child: TextField(
              controller: _phoneCtrl,
              keyboardType: TextInputType.phone,
              autofocus: true,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(15),
              ],
              onSubmitted: (_) => _loading ? null : _sendOtp(),
              decoration: const InputDecoration(
                hintText: 'Mobile number',
                floatingLabelBehavior: FloatingLabelBehavior.never,
                prefixIcon: Icon(Icons.phone_android),
                contentPadding: EdgeInsets.symmetric(
                  horizontal: AppSpacing.s4,
                  vertical: AppSpacing.s5,
                ),
                border: OutlineInputBorder(),
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: AppSpacing.s5),
      FilledButton(
        onPressed: _loading ? null : () => _sendOtp(),
        child: _loading
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Text('Send OTP'),
      ),
      const SizedBox(height: AppSpacing.s4),
      Text(
        'Standard SMS rates may apply.',
        textAlign: TextAlign.center,
        style: AppTypography.bodySmall.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
      ),
    ];
  }

  List<Widget> _otpStep() {
    return [
      TextField(
        controller: _otpCtrl,
        keyboardType: TextInputType.number,
        autofocus: true,
        textAlign: TextAlign.center,
        style: AppTypography.headlineMedium.copyWith(letterSpacing: 8),
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(6),
        ],
        onSubmitted: (_) => _loading ? null : _verifyOtp(),
        decoration: const InputDecoration(
          hintText: '••••••',
          counterText: '',
          contentPadding: EdgeInsets.symmetric(
            horizontal: AppSpacing.s4,
            vertical: AppSpacing.s5,
          ),
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(height: AppSpacing.s5),
      FilledButton(
        onPressed: _loading ? null : _verifyOtp,
        child: _loading
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Text('Verify & Continue'),
      ),
      const SizedBox(height: AppSpacing.s3),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          TextButton(
            onPressed: _loading ? null : _changeNumber,
            child: const Text('Change number'),
          ),
          TextButton(
            onPressed: (_loading || _resendSeconds > 0)
                ? null
                : () => _sendOtp(resend: true),
            child: Text(
              _resendSeconds > 0 ? 'Resend in ${_resendSeconds}s' : 'Resend code',
            ),
          ),
        ],
      ),
    ];
  }
}

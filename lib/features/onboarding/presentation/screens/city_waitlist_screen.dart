// lib/features/onboarding/presentation/screens/city_waitlist_screen.dart
//
// Shown when a user's city is not yet supported.
// Collects email and submits to the waitlist API.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/city/current_city_provider.dart';
import '../../../../design_system/tokens/spacing.dart';
import '../../../../design_system/tokens/typography.dart';

class CityWaitlistScreen extends ConsumerStatefulWidget {
  const CityWaitlistScreen({super.key});

  @override
  ConsumerState<CityWaitlistScreen> createState() => _CityWaitlistScreenState();
}

class _CityWaitlistScreenState extends ConsumerState<CityWaitlistScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();

  bool _isSubmitting = false;
  bool _submitted = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailCtrl.dispose();
    _cityCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final repo = ref.read(cityRepositoryProvider);
      final ok = await repo.joinWaitlist(
        email: _emailCtrl.text.trim(),
        cityId: _cityCtrl.text.trim().isEmpty ? null : _cityCtrl.text.trim(),
      );

      if (ok) {
        setState(() {
          _submitted = true;
          _isSubmitting = false;
        });
      } else {
        setState(() {
          _errorMessage = 'Something went wrong. Please try again.';
          _isSubmitting = false;
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage =
            'Could not connect. Check your connection and try again.';
        _isSubmitting = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Join the Waitlist'),
        backgroundColor: colorScheme.surface,
      ),
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.s6),
          child:
              _submitted
                  ? _SuccessView()
                  : _FormView(
                    formKey: _formKey,
                    emailCtrl: _emailCtrl,
                    cityCtrl: _cityCtrl,
                    isSubmitting: _isSubmitting,
                    errorMessage: _errorMessage,
                    onSubmit: _submit,
                  ),
        ),
      ),
    );
  }
}

class _FormView extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController emailCtrl;
  final TextEditingController cityCtrl;
  final bool isSubmitting;
  final String? errorMessage;
  final VoidCallback onSubmit;

  const _FormView({
    required this.formKey,
    required this.emailCtrl,
    required this.cityCtrl,
    required this.isSubmitting,
    required this.errorMessage,
    required this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Form(
      key: formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '🚇',
            style: const TextStyle(fontSize: 48),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.s4),
          Text(
            'Be first when your metro goes live',
            style: AppTypography.headlineMedium.copyWith(
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.s3),
          Text(
            "We're adding new cities every few weeks. Leave your email and we'll ping you the day your city launches on MetroSafar.",
            style: AppTypography.bodyMedium.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.s6),
          TextFormField(
            controller: emailCtrl,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Email address',
              prefixIcon: Icon(Icons.email_outlined),
              border: OutlineInputBorder(),
            ),
            validator: (v) {
              if (v == null || v.trim().isEmpty) return 'Email is required';
              if (!RegExp(r'^[^@]+@[^@]+\.[^@]+').hasMatch(v.trim())) {
                return 'Enter a valid email';
              }
              return null;
            },
          ),
          const SizedBox(height: AppSpacing.s4),
          TextFormField(
            controller: cityCtrl,
            decoration: const InputDecoration(
              labelText: 'Your city (optional)',
              hintText: 'e.g. Pune, Lucknow, Kolkata',
              prefixIcon: Icon(Icons.location_city_outlined),
              border: OutlineInputBorder(),
            ),
          ),
          if (errorMessage != null) ...[
            const SizedBox(height: AppSpacing.s3),
            Text(
              errorMessage!,
              style: AppTypography.bodySmall.copyWith(color: colorScheme.error),
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: AppSpacing.s6),
          FilledButton(
            onPressed: isSubmitting ? null : onSubmit,
            child:
                isSubmitting
                    ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                    : const Text('Join Waitlist'),
          ),
        ],
      ),
    );
  }
}

class _SuccessView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const SizedBox(height: 60),
        Text(
          '🎉',
          style: const TextStyle(fontSize: 64),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.s4),
        Text(
          "You're on the list!",
          style: AppTypography.headlineMedium.copyWith(
            fontWeight: FontWeight.w700,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.s3),
        Text(
          "We'll email you the moment your city launches on MetroSafar. Meanwhile, you can explore the app with an available city.",
          style: AppTypography.bodyMedium.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.s6),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Back to city selection'),
        ),
      ],
    );
  }
}

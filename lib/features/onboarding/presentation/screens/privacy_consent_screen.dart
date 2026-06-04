import 'dart:io';

import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../design_system/tokens/radius.dart';
import '../../../../design_system/tokens/spacing.dart';
import '../../../../design_system/tokens/typography.dart';
import '../../../../services/backend_service.dart';

class PrivacyConsentScreen extends StatefulWidget {
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  const PrivacyConsentScreen({
    required this.onAccept,
    required this.onDecline,
    super.key,
  });

  @override
  State<PrivacyConsentScreen> createState() => _PrivacyConsentScreenState();
}

class _PrivacyConsentScreenState extends State<PrivacyConsentScreen> {
  bool analyticsConsent = false;
  bool marketingConsent = false;
  bool _saving = false;

  /// Record the consent decision to the server-side DPDPA audit log, then
  /// invoke the callback. Fire-and-forget: if the network call fails we still
  /// proceed (the record will be retried on the next consent interaction).
  Future<void> _recordAndProceed(bool accepted) async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final info = await PackageInfo.fromPlatform();
      await BackendService().recordConsent(
        analyticsConsent: analyticsConsent,
        marketingConsent: marketingConsent,
        appVersion: info.version,
        platform: Platform.isAndroid ? 'android' : 'ios',
      );
    } catch (_) {
      // Non-fatal — consent record is best-effort at this stage.
    } finally {
      if (mounted) setState(() => _saving = false);
    }
    if (accepted) {
      widget.onAccept();
    } else {
      widget.onDecline();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.s6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Privacy & Consent',
                style: AppTypography.headlineSmall.copyWith(
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: AppSpacing.s4),
              Text(
                'We use analytics to understand how you use MetroSafar and improve your experience. Your privacy is important to us.',
                style: AppTypography.bodyMedium.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.s6),
              // Analytics consent checkbox
              _ConsentCheckbox(
                title: 'Analytics',
                description: 'Help us improve by sharing usage data',
                value: analyticsConsent,
                onChanged: (value) {
                  setState(() => analyticsConsent = value ?? false);
                },
              ),
              const SizedBox(height: AppSpacing.s4),
              // Marketing consent checkbox
              _ConsentCheckbox(
                title: 'Marketing Emails',
                description: 'Receive updates about new features and events (optional)',
                value: marketingConsent,
                onChanged: (value) {
                  setState(() => marketingConsent = value ?? false);
                },
              ),
              const SizedBox(height: AppSpacing.s6),
              // Privacy links — must point to live, reachable URLs (Play Store requirement).
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _PrivacyLink(
                    label: 'Privacy Policy',
                    url: 'https://metrosafar.app/privacy',
                  ),
                  _PrivacyLink(
                    label: 'Terms of Service',
                    url: 'https://metrosafar.app/terms',
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.s8),
              // Buttons — both record the decision (accept or decline) to the
              // server-side DPDPA audit log before proceeding.
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _saving ? null : () => _recordAndProceed(false),
                      child: const Text('Decline'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s4),
                  Expanded(
                    child: FilledButton(
                      onPressed: (analyticsConsent && !_saving)
                          ? () => _recordAndProceed(true)
                          : null,
                      child: _saving
                          ? const SizedBox(
                              width: 20, height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Accept'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConsentCheckbox extends StatelessWidget {
  final String title;
  final String description;
  final bool value;
  final Function(bool?) onChanged;

  const _ConsentCheckbox({
    required this.title,
    required this.description,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.s4),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainer,
          borderRadius: AppRadius.borderRadiusL,
          border: Border.all(
            color: colorScheme.outline.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          children: [
            Checkbox(
              value: value,
              onChanged: onChanged,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTypography.labelLarge.copyWith(
                      color: colorScheme.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    description,
                    style: AppTypography.bodySmall.copyWith(
                      color: colorScheme.onSurfaceVariant,
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

class _PrivacyLink extends StatelessWidget {
  final String label;
  final String url;

  const _PrivacyLink({
    required this.label,
    required this.url,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: () {
        // url is now a full absolute URL passed in by the caller.
        launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
      },
      child: Text(
        label,
        style: AppTypography.labelMedium.copyWith(
          color: colorScheme.primary,
          decoration: TextDecoration.underline,
        ),
      ),
    );
  }
}

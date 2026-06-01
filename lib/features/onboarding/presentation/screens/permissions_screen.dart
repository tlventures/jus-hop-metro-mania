import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../../design_system/tokens/colors.dart';
import '../../../../design_system/tokens/radius.dart';
import '../../../../design_system/tokens/spacing.dart';
import '../../../../design_system/tokens/typography.dart';

class PermissionsScreen extends StatefulWidget {
  final VoidCallback onComplete;
  final VoidCallback onBack;

  const PermissionsScreen({
    required this.onComplete,
    required this.onBack,
    super.key,
  });

  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends State<PermissionsScreen> {
  bool locationGranted = false;
  bool notificationGranted = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.s6),
          child: Column(
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      '🔔',
                      style: AppTypography.displayLarge.copyWith(fontSize: 100),
                    ),
                    const SizedBox(height: AppSpacing.s6),
                    Text(
                      'Enable Notifications',
                      style: AppTypography.headlineLarge.copyWith(
                        color: colorScheme.onSurface,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppSpacing.s6),
                    // Location Permission Card
                    _PermissionCard(
                      icon: '📍',
                      title: 'Location Access',
                      description: 'Show nearby metro stations',
                      granted: locationGranted,
                      onRequest: _requestLocationPermission,
                    ),
                    const SizedBox(height: AppSpacing.s4),
                    // Notification Permission Card
                    _PermissionCard(
                      icon: '🔔',
                      title: 'Notifications',
                      description: 'Reminders for streaks and quests',
                      granted: notificationGranted,
                      onRequest: _requestNotificationPermission,
                    ),
                    const SizedBox(height: AppSpacing.s4),
                    Text(
                      'You can change these later in settings',
                      style: AppTypography.bodySmall.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: widget.onBack,
                      child: const Text('Back'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s4),
                  Expanded(
                    child: FilledButton(
                      onPressed: widget.onComplete,
                      child: const Text('Done'),
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

  Future<void> _requestLocationPermission() async {
    final status = await Permission.location.request();
    setState(() {
      locationGranted = status.isGranted;
    });
  }

  Future<void> _requestNotificationPermission() async {
    final status = await Permission.notification.request();
    setState(() {
      notificationGranted = status.isGranted;
    });
  }
}

class _PermissionCard extends StatelessWidget {
  final String icon;
  final String title;
  final String description;
  final bool granted;
  final VoidCallback onRequest;

  const _PermissionCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.granted,
    required this.onRequest,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.s4),
      decoration: BoxDecoration(
        color: granted
            ? AppColors.mintSuccess.withValues(alpha: 0.1)
            : colorScheme.surfaceContainer,
        borderRadius: AppRadius.borderRadiusL,
        border: Border.all(
          color: granted
              ? AppColors.mintSuccess.withValues(alpha: 0.5)
              : colorScheme.outline.withValues(alpha: 0.3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(icon, style: const TextStyle(fontSize: 38)),
              const SizedBox(width: AppSpacing.s4),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.labelLarge.copyWith(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.s1),
                    Text(
                      description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodySmall.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (granted)
                Container(
                  padding: const EdgeInsets.all(AppSpacing.s2),
                  decoration: const BoxDecoration(
                    color: Colors.green,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
            ],
          ),
          if (!granted) ...[
            const SizedBox(height: AppSpacing.s3),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton(
                onPressed: onRequest,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.s5,
                    vertical: AppSpacing.s2,
                  ),
                ),
                child: const Text('Allow'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

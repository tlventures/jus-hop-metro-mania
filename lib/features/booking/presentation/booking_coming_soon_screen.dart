import 'package:flutter/material.dart';
import '../../../design_system/tokens/colors.dart';
import '../../../design_system/tokens/radius.dart';
import '../../../design_system/tokens/spacing.dart';
import '../../../design_system/tokens/typography.dart';
import '../../../services/backend_service.dart';

class BookingComingSoonScreen extends StatefulWidget {
  const BookingComingSoonScreen({super.key});

  @override
  State<BookingComingSoonScreen> createState() => _BookingComingSoonScreenState();
}

class _BookingComingSoonScreenState extends State<BookingComingSoonScreen> {
  bool _joined = false;
  bool _loading = false;

  Future<void> _joinWaitlist() async {
    setState(() => _loading = true);
    try {
      final result = await BackendService().joinWaitlist();
      final alreadyJoined = result['alreadyJoined'] as bool? ?? false;
      setState(() {
        _joined = true;
        _loading = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              alreadyJoined
                  ? 'You\'re already on the waitlist!'
                  : '✓ Added to waitlist! We\'ll notify you when booking launches.',
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint('BookingScreen.joinWaitlist error: $e');
      setState(() => _loading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not join waitlist. Please try again.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('Ticket Booking', style: AppTypography.headlineMedium),
      ),
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.s6),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.gradientStart.withValues(alpha: 0.2),
                    AppColors.gradientEnd.withValues(alpha: 0.2),
                  ],
                ),
                borderRadius: AppRadius.borderRadiusXL,
              ),
              child: Center(
                child: Text('🎫', style: AppTypography.displayLarge),
              ),
            ),
            const SizedBox(height: AppSpacing.s8),
            Text(
              'Booking Coming Soon',
              style: AppTypography.headlineLarge.copyWith(
                color: colorScheme.onSurface,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.s4),
            Text(
              'We\'re integrating with metro networks across India to bring you seamless ticket booking. Join the waitlist to be notified first!',
              style: AppTypography.bodyMedium.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.s8),
            if (_joined)
              Container(
                padding: const EdgeInsets.all(AppSpacing.s4),
                decoration: BoxDecoration(
                  color: AppColors.mintSuccess.withValues(alpha: 0.1),
                  borderRadius: AppRadius.borderRadiusL,
                  border:
                      Border.all(color: AppColors.mintSuccess.withValues(alpha: 0.4)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.check_circle, color: AppColors.success),
                    const SizedBox(width: AppSpacing.s3),
                    Text(
                      'You\'re on the waitlist!',
                      style: AppTypography.labelLarge.copyWith(
                        color: AppColors.mintSuccess,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              )
            else
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _loading ? null : _joinWaitlist,
                  child: _loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Notify Me When Ready'),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

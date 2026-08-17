// lib/features/booking/presentation/ticket_details_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../design_system/tokens/colors.dart';
import '../../../design_system/tokens/radius.dart';
import '../../../design_system/tokens/spacing.dart';
import '../../../design_system/tokens/typography.dart';
import '../application/ticketing_provider.dart';

class TicketDetailsScreen extends ConsumerWidget {
  const TicketDetailsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final state = ref.watch(ticketingNotifierProvider);
    final ticket = state.activeTicket;

    return Scaffold(
      appBar: AppBar(
        title: Text('Metro QR Ticket', style: AppTypography.headlineMedium),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () => context.go('/home'),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.s4),
          child: Column(
            children: [
              // Success Banner
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.s3),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.15),
                  borderRadius: AppRadius.borderRadiusM,
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.check_circle_rounded, color: Colors.green),
                    SizedBox(width: 8),
                    Text(
                      'Ticket Booked Successfully!',
                      style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              if ((ticket?.pointsEarned ?? 0) > 0) ...[
                const SizedBox(height: AppSpacing.s3),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.s4,
                    vertical: AppSpacing.s3,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.10),
                    borderRadius: AppRadius.borderRadiusM,
                    border: Border.all(
                      color: AppColors.primary.withValues(alpha: 0.30),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.stars_rounded, color: AppColors.primary),
                      const SizedBox(width: 8),
                      Text(
                        'You earned ${ticket!.pointsEarned} reward points',
                        style: AppTypography.titleMedium.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.s5),

              // Main Ticket Pass Container
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(borderRadius: AppRadius.borderRadiusXL),
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.s6),
                  child: Column(
                    children: [
                      // Metro Branding Header
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.subway_rounded, color: AppColors.electricTeal, size: 28),
                              const SizedBox(width: 8),
                              Text('Hyderabad Metro', style: AppTypography.titleLarge),
                            ],
                          ),
                          Chip(
                            label: Text(ticket?.ticketType ?? 'SJT'),
                            backgroundColor: AppColors.primary.withValues(alpha: 0.15),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.s4),

                      // Station Journey Row
                      Container(
                        padding: const EdgeInsets.all(AppSpacing.s4),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerLow,
                          borderRadius: AppRadius.borderRadiusL,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Origin', style: AppTypography.bodySmall),
                                const SizedBox(height: 2),
                                Text(
                                  ticket?.originStation ?? state.originStation?.name ?? 'Miyapur',
                                  style: AppTypography.titleMedium.copyWith(color: Colors.green),
                                ),
                              ],
                            ),
                            const Icon(Icons.east_rounded, color: AppColors.electricTeal),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text('Destination', style: AppTypography.bodySmall),
                                const SizedBox(height: 2),
                                Text(
                                  ticket?.destinationStation ?? state.destinationStation?.name ?? 'LB Nagar',
                                  style: AppTypography.titleMedium.copyWith(color: Colors.redAccent),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.s6),

                      // QR Code Display Card
                      Container(
                        width: 220,
                        height: 220,
                        padding: const EdgeInsets.all(AppSpacing.s4),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: AppRadius.borderRadiusL,
                          border: Border.all(color: Colors.grey.shade300, width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.08),
                              blurRadius: 10,
                              spreadRadius: 2,
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.qr_code_2_rounded, size: 140, color: Colors.black),
                            const SizedBox(height: 4),
                            Text(
                              'SCAN AT TURNSTILE',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.grey.shade800,
                                letterSpacing: 1.2,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: AppSpacing.s4),

                      Text(
                        'Token: ${ticket?.qrPayload ?? "ONDC:METRO:HYD:ACTIVE"}',
                        style: AppTypography.bodySmall.copyWith(fontFamily: 'monospace'),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: AppSpacing.s6),

                      const Divider(),
                      const SizedBox(height: AppSpacing.s3),

                      // Ticket Specs Grid
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Passengers', style: AppTypography.bodySmall),
                              Text('${ticket?.passengerCount ?? state.passengerCount}', style: AppTypography.titleMedium),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Text('Total Fare', style: AppTypography.bodySmall),
                              Text('₹${(ticket?.totalFare ?? 35).toStringAsFixed(0)}', style: AppTypography.titleMedium.copyWith(color: AppColors.primary)),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text('Valid Until', style: AppTypography.bodySmall),
                              Text(
                                '${DateTime.now().add(const Duration(hours: 4)).hour}:${DateTime.now().minute.toString().padLeft(2, "0")}',
                                style: AppTypography.titleMedium.copyWith(color: Colors.orange),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.s6),

              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => context.go('/home'),
                      icon: const Icon(Icons.home_rounded),
                      label: const Text('Home'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s4),
                  Expanded(
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                      ),
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Ticket saved to your active wallet!'),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      },
                      icon: const Icon(Icons.download_rounded),
                      label: const Text('Save Ticket'),
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

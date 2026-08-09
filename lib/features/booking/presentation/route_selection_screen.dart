// lib/features/booking/presentation/route_selection_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../design_system/tokens/colors.dart';
import '../../../design_system/tokens/radius.dart';
import '../../../design_system/tokens/spacing.dart';
import '../../../design_system/tokens/typography.dart';
import '../application/ticketing_provider.dart';

class RouteSelectionScreen extends ConsumerWidget {
  const RouteSelectionScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final state = ref.watch(ticketingNotifierProvider);
    final notifier = ref.read(ticketingNotifierProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: Text('Select Route & Ticket', style: AppTypography.headlineMedium),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.s4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Route Summary Header
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(AppSpacing.s4),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHigh,
                  borderRadius: AppRadius.borderRadiusL,
                ),
                child: Row(
                  children: [
                    const Icon(Icons.directions_subway_filled_rounded, color: AppColors.electricTeal, size: 28),
                    const SizedBox(width: AppSpacing.s3),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '${state.originStation?.name ?? "Origin"} ➔ ${state.destinationStation?.name ?? "Destination"}',
                            style: AppTypography.titleMedium,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '8 Stops • Est. 24 Mins',
                            style: AppTypography.bodySmall.copyWith(color: colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.s6),

              Text('Available Ticket Types', style: AppTypography.titleLarge),
              const SizedBox(height: AppSpacing.s4),

              // Options list (SJT / RJT)
              Expanded(
                child: ListView.builder(
                  itemCount: state.availableOptions.length,
                  itemBuilder: (context, index) {
                    final option = state.availableOptions[index];
                    final isSelected = state.selectedOption?.id == option.id;

                    return Card(
                      margin: const EdgeInsets.only(bottom: AppSpacing.s4),
                      shape: RoundedRectangleBorder(
                        borderRadius: AppRadius.borderRadiusL,
                        side: BorderSide(
                          color: isSelected ? AppColors.primary : colorScheme.outlineVariant.withValues(alpha: 0.3),
                          width: isSelected ? 2 : 1,
                        ),
                      ),
                      elevation: isSelected ? 2 : 0,
                      child: InkWell(
                        onTap: () => notifier.selectOption(option),
                        borderRadius: AppRadius.borderRadiusL,
                        child: Padding(
                          padding: const EdgeInsets.all(AppSpacing.s4),
                          child: Row(
                            children: [
                              Radio<String>(
                                value: option.id,
                                groupValue: state.selectedOption?.id,
                                onChanged: (_) => notifier.selectOption(option),
                                activeColor: AppColors.primary,
                              ),
                              const SizedBox(width: AppSpacing.s2),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(option.title, style: AppTypography.titleMedium),
                                    const SizedBox(height: 4),
                                    Text(
                                      option.type == 'SJT'
                                          ? 'Valid for single entry & exit today'
                                          : 'Valid for return journey within 24 hrs',
                                      style: AppTypography.bodySmall,
                                    ),
                                  ],
                                ),
                              ),
                              Text(
                                '₹${option.fare.toStringAsFixed(0)}',
                                style: AppTypography.headlineSmall.copyWith(
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),

              // Passenger Count Selector
              Container(
                padding: const EdgeInsets.all(AppSpacing.s4),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerLow,
                  borderRadius: AppRadius.borderRadiusL,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Passenger Count', style: AppTypography.titleMedium),
                    Row(
                      children: [
                        IconButton.filledTonal(
                          onPressed: state.passengerCount > 1
                              ? () => notifier.setPassengerCount(state.passengerCount - 1)
                              : null,
                          icon: const Icon(Icons.remove_rounded),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s4),
                          child: Text('${state.passengerCount}', style: AppTypography.titleLarge),
                        ),
                        IconButton.filledTonal(
                          onPressed: state.passengerCount < 6
                              ? () => notifier.setPassengerCount(state.passengerCount + 1)
                              : null,
                          icon: const Icon(Icons.add_rounded),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.s4),

              // Bottom Total & Proceed Button
              Row(
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Total Fare', style: AppTypography.bodySmall),
                      Text(
                        '₹${((state.selectedOption?.fare ?? 0) * state.passengerCount).toStringAsFixed(0)}',
                        style: AppTypography.headlineLarge.copyWith(color: AppColors.primary),
                      ),
                    ],
                  ),
                  const SizedBox(width: AppSpacing.s6),
                  Expanded(
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
                        shape: RoundedRectangleBorder(borderRadius: AppRadius.borderRadiusL),
                      ),
                      onPressed: state.selectedOption != null
                          ? () => context.push('/booking/checkout')
                          : null,
                      child: Text('Proceed to Checkout', style: AppTypography.titleMedium.copyWith(color: Colors.white)),
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

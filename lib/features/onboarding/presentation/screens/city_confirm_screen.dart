// lib/features/onboarding/presentation/screens/city_confirm_screen.dart
//
// Shown after the permissions screen. Detects the user's city from GPS,
// confirms it (or lets them pick manually), then proceeds to the app.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import '../../../../core/city/city_model.dart';
import '../../../../core/city/current_city_provider.dart';
import '../../../../design_system/tokens/spacing.dart';
import '../../../../design_system/tokens/typography.dart';
import 'city_waitlist_screen.dart';

class CityConfirmScreen extends ConsumerStatefulWidget {
  final VoidCallback onCityConfirmed;
  final VoidCallback onBack;

  const CityConfirmScreen({
    super.key,
    required this.onCityConfirmed,
    required this.onBack,
  });

  @override
  ConsumerState<CityConfirmScreen> createState() => _CityConfirmScreenState();
}

class _CityConfirmScreenState extends ConsumerState<CityConfirmScreen> {
  _ScreenState _state = _ScreenState.detecting;
  String? _detectedCityId;
  Map<String, String>? _detectedCityName;
  List<CitySummary> _allCities = [];

  @override
  void initState() {
    super.initState();
    _detectCity();
  }

  Future<void> _detectCity() async {
    setState(() => _state = _ScreenState.detecting);
    try {
      final repo = ref.read(cityRepositoryProvider);

      // Load city list in parallel with geo lookup
      final citiesFuture = repo.fetchCitySummaries();

      Position? position;
      try {
        final permission = await Geolocator.checkPermission();
        if (permission != LocationPermission.denied &&
            permission != LocationPermission.deniedForever) {
          position = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.medium,
          ).timeout(const Duration(seconds: 6));
        }
      } catch (_) {
        /* location unavailable — fall through to city picker */
      }

      _allCities = await citiesFuture;

      if (position != null) {
        final result = await repo.resolveCity(
          position.latitude,
          position.longitude,
        );
        final status = result['status'] as String? ?? 'error';

        if (status == 'found' || status == 'nearby') {
          _detectedCityId = result['cityId'] as String;
          _detectedCityName =
              result['city'] != null
                  ? Map<String, String>.from(result['city'] as Map)
                  : null;
          setState(() => _state = _ScreenState.confirm);
          return;
        }

        if (status == 'unsupported') {
          setState(() => _state = _ScreenState.unsupported);
          return;
        }
      }

      // No location or no city matched — show picker
      setState(() => _state = _ScreenState.picker);
    } catch (e) {
      setState(() {
        _state = _ScreenState.picker;
      });
    }
  }

  Future<void> _confirmCity(String cityId) async {
    await ref.read(currentCityProvider.notifier).confirmCity(cityId);
    widget.onCityConfirmed();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: switch (_state) {
          _ScreenState.detecting => _DetectingView(),
          _ScreenState.confirm => _ConfirmView(
            cityId: _detectedCityId!,
            cityName: _detectedCityName ?? {'en': _detectedCityId!},
            onConfirm: () => _confirmCity(_detectedCityId!),
            onChange: () => setState(() => _state = _ScreenState.picker),
          ),
          _ScreenState.picker => _PickerView(
            cities: _allCities,
            onPick: _confirmCity,
            onBack: widget.onBack,
          ),
          _ScreenState.unsupported => _UnsupportedView(
            cities: _allCities,
            onJoinWaitlist:
                () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const CityWaitlistScreen()),
                ),
            onPickExisting: () => setState(() => _state = _ScreenState.picker),
          ),
        },
      ),
    );
  }
}

enum _ScreenState { detecting, confirm, picker, unsupported }

// ─────────────────────────────────────────────────────────────────────────────

class _DetectingView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: colorScheme.primary),
          const SizedBox(height: AppSpacing.s4),
          Text(
            'Detecting your city…',
            style: AppTypography.bodyLarge.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _ConfirmView extends StatelessWidget {
  final String cityId;
  final Map<String, String> cityName;
  final VoidCallback onConfirm;
  final VoidCallback onChange;

  const _ConfirmView({
    required this.cityId,
    required this.cityName,
    required this.onConfirm,
    required this.onChange,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final name = cityName['en'] ?? cityId;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.s6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(),
          Text(
            '📍',
            style: const TextStyle(fontSize: 56),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.s4),
          Text(
            'Looks like you\'re in',
            style: AppTypography.titleMedium.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.s2),
          Text(
            name,
            style: AppTypography.headlineLarge.copyWith(
              color: colorScheme.primary,
              fontWeight: FontWeight.w800,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.s3),
          Text(
            'We\'ll set up your stations, language, and local vibe.',
            style: AppTypography.bodyMedium.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const Spacer(),
          FilledButton(onPressed: onConfirm, child: Text('Yes, I\'m in $name')),
          const SizedBox(height: AppSpacing.s3),
          TextButton(
            onPressed: onChange,
            child: const Text('Choose a different city'),
          ),
          const SizedBox(height: AppSpacing.s4),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _PickerView extends StatelessWidget {
  final List<CitySummary> cities;
  final Future<void> Function(String cityId) onPick;
  final VoidCallback onBack;

  const _PickerView({
    required this.cities,
    required this.onPick,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final liveCities =
        cities
            .where(
              (c) => c.status == CityStatus.live || c.status == CityStatus.beta,
            )
            .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.s4,
            AppSpacing.s4,
            AppSpacing.s4,
            0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextButton.icon(
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back),
                label: const Text('Back'),
              ),
              const SizedBox(height: AppSpacing.s3),
              Text(
                'Choose your city',
                style: AppTypography.headlineMedium.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.s1),
              Text(
                'Pick the metro city you commute in.',
                style: AppTypography.bodyMedium.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.s4),
        Expanded(
          child:
              liveCities.isEmpty
                  ? Center(
                    child: Text(
                      'No cities available yet.',
                      style: AppTypography.bodyMedium,
                    ),
                  )
                  : ListView.separated(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.s4,
                    ),
                    itemCount: liveCities.length,
                    separatorBuilder:
                        (_, __) => const SizedBox(height: AppSpacing.s2),
                    itemBuilder: (context, i) {
                      final city = liveCities[i];
                      final isBeta = city.status == CityStatus.beta;
                      return Card(
                        child: ListTile(
                          title: Text(
                            city.displayName('en'),
                            style: AppTypography.titleMedium,
                          ),
                          subtitle: Text(
                            city.operatorShortName,
                            style: AppTypography.bodySmall.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                          trailing:
                              isBeta
                                  ? Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: colorScheme.secondaryContainer,
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      'Beta',
                                      style: AppTypography.labelSmall.copyWith(
                                        color: colorScheme.secondary,
                                      ),
                                    ),
                                  )
                                  : const Icon(
                                    Icons.arrow_forward_ios,
                                    size: 16,
                                  ),
                          onTap: () => onPick(city.id),
                        ),
                      );
                    },
                  ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _UnsupportedView extends StatelessWidget {
  final List<CitySummary> cities;
  final VoidCallback onJoinWaitlist;
  final VoidCallback onPickExisting;

  const _UnsupportedView({
    required this.cities,
    required this.onJoinWaitlist,
    required this.onPickExisting,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.s6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(),
          Text(
            '🚧',
            style: const TextStyle(fontSize: 56),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.s4),
          Text(
            'Your city isn\'t on MetroSafar yet',
            style: AppTypography.headlineMedium.copyWith(
              fontWeight: FontWeight.w700,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.s3),
          Text(
            'We\'re expanding fast! Join the waitlist and be first to know when your metro launches on MetroSafar.',
            style: AppTypography.bodyMedium.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
          const Spacer(),
          FilledButton(
            onPressed: onJoinWaitlist,
            child: const Text('Join the waitlist'),
          ),
          const SizedBox(height: AppSpacing.s3),
          OutlinedButton(
            onPressed: onPickExisting,
            child: const Text('Explore an available city'),
          ),
          const SizedBox(height: AppSpacing.s4),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:metrosafar/core/city/current_city_provider.dart';
import 'package:metrosafar/design_system/tokens/radius.dart';
import 'package:metrosafar/design_system/tokens/spacing.dart';
import 'package:metrosafar/design_system/tokens/typography.dart';
import 'package:metrosafar/models/metro_station.dart';
import 'package:metrosafar/services/backend_service.dart';

class JourneyPlannerScreen extends ConsumerStatefulWidget {
  const JourneyPlannerScreen({super.key});

  @override
  ConsumerState<JourneyPlannerScreen> createState() => _JourneyPlannerScreenState();
}

class _JourneyPlannerScreenState extends ConsumerState<JourneyPlannerScreen> {
  final BackendService _backendService = BackendService();
  List<MetroStation> _stations = [];
  String? _from;
  String? _to;
  Map<String, dynamic>? _route;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // Use city-scoped stations from CurrentCityProvider.
    // Falls back to backend API if provider not yet loaded.
    final cityStations = ref.read(cityStationsProvider);
    final stations = cityStations.isNotEmpty
        ? cityStations
        : await _backendService.getStations();
    setState(() {
      _stations = stations;
      _from = stations.isNotEmpty ? stations.first.id : null;
      _to = stations.length > 5 ? stations[5].id : _from;
      _loading = false;
    });
  }

  Future<void> _plan() async {
    if (_from == null || _to == null) return;
    setState(() => _loading = true);
    final route = await _backendService.getRoute(
      fromStationId: _from!,
      toStationId: _to!,
    );
    setState(() {
      _route = route;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final options = (_route?['options'] as List<dynamic>? ?? []);

    return Scaffold(
      appBar: AppBar(title: const Text('Journey Planner')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.s6),
        children: [
          Text(
            'Expected timetable routing',
            style: AppTypography.headlineMedium.copyWith(
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: AppSpacing.s2),
          Text(
            'This uses the static timetable source until an official live metro feed is connected.',
            style: AppTypography.bodyMedium.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.s6),
          _StationDropdown(
            label: 'From',
            value: _from,
            stations: _stations,
            onChanged: (value) => setState(() => _from = value),
          ),
          const SizedBox(height: AppSpacing.s4),
          _StationDropdown(
            label: 'To',
            value: _to,
            stations: _stations,
            onChanged: (value) => setState(() => _to = value),
          ),
          const SizedBox(height: AppSpacing.s6),
          FilledButton.icon(
            onPressed: _loading ? null : _plan,
            icon: const Icon(Icons.route_outlined),
            label: const Text('Plan route'),
          ),
          const SizedBox(height: AppSpacing.s6),
          if (_loading) const LinearProgressIndicator(),
          ...options.map((option) {
            final map = Map<String, dynamic>.from(option as Map);
            final duration =
                ((map['durationSeconds'] as num? ?? 0) / 60).round();
            return Container(
              margin: const EdgeInsets.only(bottom: AppSpacing.s4),
              padding: const EdgeInsets.all(AppSpacing.s4),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainer,
                borderRadius: AppRadius.borderRadiusXL,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    map['summary'] as String? ?? 'Metro route',
                    style: AppTypography.titleMedium.copyWith(
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.s2),
                  Text(
                    '$duration min - fare estimate Rs ${map['fareEstimate'] ?? '--'} - ${map['confidence'] ?? 'timetable'}',
                    style: AppTypography.bodyMedium.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _StationDropdown extends StatelessWidget {
  final String label;
  final String? value;
  final List<MetroStation> stations;
  final ValueChanged<String?> onChanged;

  const _StationDropdown({
    required this.label,
    required this.value,
    required this.stations,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: stations.any((station) => station.id == value) ? value : null,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(borderRadius: AppRadius.borderRadiusL),
      ),
      items:
          stations
              .map(
                (station) => DropdownMenuItem(
                  value: station.id,
                  child: Text(station.name),
                ),
              )
              .toList(),
      onChanged: onChanged,
    );
  }
}

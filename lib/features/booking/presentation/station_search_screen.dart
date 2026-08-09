// lib/features/booking/presentation/station_search_screen.dart

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';

import '../../../design_system/components/ad_banner.dart';
import '../../../design_system/tokens/colors.dart';
import '../../../design_system/tokens/radius.dart';
import '../../../design_system/tokens/spacing.dart';
import '../../../design_system/tokens/typography.dart';
import '../../../models/metro_station.dart';
import '../../../services/location_service.dart';
import '../application/ticketing_provider.dart';

class StationSearchScreen extends ConsumerStatefulWidget {
  const StationSearchScreen({super.key});

  @override
  ConsumerState<StationSearchScreen> createState() => _StationSearchScreenState();
}

class _StationSearchScreenState extends ConsumerState<StationSearchScreen> {
  MetroStation? _origin;
  MetroStation? _destination;

  static final List<MetroStation> _stations = [
    MetroStation(id: 'hyd_red_01', code: 'MYP', name: 'Miyapur',
      line: 'Red Line', lineIds: ['red'], distance: 0, latitude: 17.4959, longitude: 78.3612),
    MetroStation(id: 'hyd_red_03', code: 'JNTU', name: 'JNTU College',
      line: 'Red Line', lineIds: ['red'], distance: 0, latitude: 17.4923, longitude: 78.3862),
    MetroStation(id: 'hyd_red_04', code: 'KPHB', name: 'KPHB Colony',
      line: 'Red Line', lineIds: ['red'], distance: 0, latitude: 17.4849, longitude: 78.3915),
    MetroStation(id: 'hyd_red_11', code: 'AMP', name: 'Ameerpet',
      line: 'Red & Blue Lines', lineIds: ['red', 'blue'], distance: 0, latitude: 17.4374, longitude: 78.4482),
    MetroStation(id: 'hyd_red_18', code: 'MGBS', name: 'MG Bus Station',
      line: 'Red & Green Lines', lineIds: ['red', 'green'], distance: 0, latitude: 17.3782, longitude: 78.4867),
    MetroStation(id: 'hyd_red_27', code: 'LBN', name: 'LB Nagar',
      line: 'Red Line', lineIds: ['red'], distance: 0, latitude: 17.3479, longitude: 78.5525),
    MetroStation(id: 'hyd_blue_01', code: 'NGL', name: 'Nagole',
      line: 'Blue Line', lineIds: ['blue'], distance: 0, latitude: 17.3820, longitude: 78.5583),
    MetroStation(id: 'hyd_blue_15', code: 'HTC', name: 'Hitec City',
      line: 'Blue Line', lineIds: ['blue'], distance: 0, latitude: 17.4483, longitude: 78.3782),
    MetroStation(id: 'hyd_blue_16', code: 'RDG', name: 'Raidurg',
      line: 'Blue Line', lineIds: ['blue'], distance: 0, latitude: 17.4413, longitude: 78.3792),
    MetroStation(id: 'hyd_green_01', code: 'JBS', name: 'Jubilee Bus Station',
      line: 'Green Line', lineIds: ['green'], distance: 0, latitude: 17.4437, longitude: 78.4956),
  ];

  /// Same list, but with `.distance` populated once the GPS returns and sorted
  /// nearest-first. Used by the picker sheet so the user sees closest stations
  /// at the top.
  late List<MetroStation> _ranked = List.of(_stations);
  bool _locating = false;
  bool _autoDetected = false;

  @override
  void initState() {
    super.initState();
    _origin = _stations.firstWhere((s) => s.code == 'MYP');
    _destination = _stations.firstWhere((s) => s.code == 'LBN');
    WidgetsBinding.instance.addPostFrameCallback((_) => _detectNearest());
  }

  Future<void> _detectNearest() async {
    setState(() => _locating = true);
    try {
      final pos = await LocationService().getCurrentLocation();
      final ranked = _stations.map((s) {
        final km = Geolocator.distanceBetween(
                pos.latitude, pos.longitude, s.latitude, s.longitude) / 1000;
        return s.copyWith(distance: double.parse(km.toStringAsFixed(1)));
      }).toList()
        ..sort((a, b) => a.distance.compareTo(b.distance));

      if (!mounted) return;
      final nearest = ranked.first;
      final defaultDest = ranked.skip(1).firstWhere(
            (s) => s.lineIds.any(nearest.lineIds.contains),
            orElse: () => ranked.last,
          );
      setState(() {
        _ranked = ranked;
        _origin = nearest;
        _destination = defaultDest;
        _autoDetected = true;
      });
    } catch (e) {
      if (kDebugMode) debugPrint('Nearest-station detect failed: $e');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _swap() {
    setState(() {
      final t = _origin;
      _origin = _destination;
      _destination = t;
    });
  }

  Color _lineColor(String line) {
    if (line.contains('Red')) return Colors.redAccent;
    if (line.contains('Blue')) return Colors.blueAccent;
    if (line.contains('Green')) return Colors.green;
    return AppColors.primary;
  }

  Future<void> _pickStation({required bool origin}) async {
    final excluded = origin ? _destination?.id : _origin?.id;
    final selected = await showModalBottomSheet<MetroStation>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: RoundedRectangleBorder(borderRadius: AppRadius.borderRadiusXL),
      builder: (ctx) => _StationPickerSheet(
        title: origin ? 'Select origin' : 'Select destination',
        stations: _ranked.where((s) => s.id != excluded).toList(),
        onLineColor: _lineColor,
      ),
    );
    if (selected == null || !mounted) return;
    setState(() {
      if (origin) {
        _origin = selected;
      } else {
        _destination = selected;
      }
    });
  }

  bool get _canProceed =>
      _origin != null && _destination != null && _origin!.id != _destination!.id;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final state = ref.watch(ticketingNotifierProvider);
    final searching = state.status == BookingStatus.searching;

    return Scaffold(
      appBar: AppBar(
        title: Text('Where to?', style: AppTypography.headlineMedium),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.s4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_locating)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.s3),
                  child: Row(
                    children: [
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      const SizedBox(width: 8),
                      Text('Finding your nearest station…',
                          style: AppTypography.bodySmall),
                    ],
                  ),
                ),

              Container(
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHigh,
                  borderRadius: AppRadius.borderRadiusL,
                ),
                child: Column(
                  children: [
                    _StationRow(
                      icon: Icons.my_location_rounded,
                      iconColor: Colors.green,
                      label: 'From',
                      station: _origin,
                      hint: _autoDetected ? 'Nearest station' : 'Pick origin',
                      onTap: () => _pickStation(origin: true),
                    ),
                    Divider(height: 1, color: cs.outlineVariant),
                    Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: IconButton.filledTonal(
                          onPressed: _swap,
                          icon: const Icon(Icons.swap_vert_rounded),
                          tooltip: 'Swap',
                        ),
                      ),
                    ),
                    Divider(height: 1, color: cs.outlineVariant),
                    _StationRow(
                      icon: Icons.location_on_rounded,
                      iconColor: Colors.redAccent,
                      label: 'To',
                      station: _destination,
                      hint: 'Pick destination',
                      onTap: () => _pickStation(origin: false),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: AppSpacing.s3),
              Text(
                'Tap From or To to change. We autofilled based on your location.',
                style: AppTypography.bodySmall.copyWith(color: cs.onSurfaceVariant),
              ),

              if (state.errorMessage != null) ...[
                const SizedBox(height: AppSpacing.s3),
                Container(
                  padding: const EdgeInsets.all(AppSpacing.s3),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.08),
                    borderRadius: AppRadius.borderRadiusM,
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: Colors.red),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(state.errorMessage!,
                            style: const TextStyle(color: Colors.red)),
                      ),
                    ],
                  ),
                ),
              ],

              // Ad slot — this is a browsing screen, not a payment step, so it
              // is a policy-safe place for an ad. The Spacer below keeps it well
              // clear of the Continue button.
              const SizedBox(height: AppSpacing.s4),
              const Center(child: MetroSafarAdBanner()),

              const Spacer(),

              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
                    shape: RoundedRectangleBorder(
                      borderRadius: AppRadius.borderRadiusL,
                    ),
                  ),
                  onPressed: (!_canProceed || searching)
                      ? null
                      : () async {
                          ref
                              .read(ticketingNotifierProvider.notifier)
                              .setStations(_origin!, _destination!);
                          await ref
                              .read(ticketingNotifierProvider.notifier)
                              .searchRoutes();
                          if (context.mounted) {
                            context.push('/booking/routes');
                          }
                        },
                  icon: searching
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.arrow_forward_rounded),
                  label: Text(
                    searching ? 'Finding routes…' : 'Continue',
                    style: AppTypography.titleMedium.copyWith(color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StationRow extends StatelessWidget {
  const _StationRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.station,
    required this.hint,
    required this.onTap,
  });

  final IconData icon;
  final Color iconColor;
  final String label;
  final MetroStation? station;
  final String hint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.borderRadiusL,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s4),
        child: Row(
          children: [
            Icon(icon, color: iconColor, size: 24),
            const SizedBox(width: AppSpacing.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: AppTypography.bodySmall
                        .copyWith(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    station?.name ?? hint,
                    style: AppTypography.titleMedium.copyWith(
                      fontWeight: FontWeight.w700,
                      color: station != null ? cs.onSurface : cs.outline,
                    ),
                  ),
                  if (station != null)
                    Text(
                      station!.distance > 0
                          ? '${station!.line} · ${station!.distance.toStringAsFixed(1)} km away'
                          : station!.line,
                      style: AppTypography.bodySmall
                          .copyWith(color: cs.onSurfaceVariant),
                    ),
                ],
              ),
            ),
            Icon(Icons.keyboard_arrow_down_rounded, color: cs.onSurfaceVariant),
          ],
        ),
      ),
    );
  }
}

class _StationPickerSheet extends StatefulWidget {
  const _StationPickerSheet({
    required this.title,
    required this.stations,
    required this.onLineColor,
  });

  final String title;
  final List<MetroStation> stations;
  final Color Function(String) onLineColor;

  @override
  State<_StationPickerSheet> createState() => _StationPickerSheetState();
}

class _StationPickerSheetState extends State<_StationPickerSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.toLowerCase();
    final filtered = widget.stations.where((s) {
      return s.name.toLowerCase().contains(q) ||
          (s.code?.toLowerCase().contains(q) ?? false) ||
          s.line.toLowerCase().contains(q);
    }).toList();

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      builder: (ctx, scrollController) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.s4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(widget.title,
                        style: AppTypography.headlineSmall),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s4),
              child: TextField(
                autofocus: false,
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  hintText: 'Search stations…',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: AppRadius.borderRadiusL,
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.s3),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s4),
                itemCount: filtered.length,
                itemBuilder: (context, i) {
                  final s = filtered[i];
                  final color = widget.onLineColor(s.line);
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: color.withValues(alpha: 0.15),
                      child: Text(
                        s.code ?? s.name.substring(0, 2).toUpperCase(),
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    title: Text(s.name, style: AppTypography.titleMedium),
                    subtitle: Text(
                      s.distance > 0
                          ? '${s.line} · ${s.distance.toStringAsFixed(1)} km'
                          : s.line,
                      style: AppTypography.bodySmall,
                    ),
                    onTap: () => Navigator.pop(context, s),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

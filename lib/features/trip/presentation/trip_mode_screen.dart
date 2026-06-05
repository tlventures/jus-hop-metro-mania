import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:metrosafar/design_system/tokens/colors.dart';
import 'package:metrosafar/design_system/tokens/radius.dart';
import 'package:metrosafar/design_system/tokens/spacing.dart';
import 'package:metrosafar/design_system/tokens/typography.dart';
import 'package:metrosafar/features/trip/application/trip_state_provider.dart';
import 'package:metrosafar/models/metro_station.dart';

class TripModeScreen extends ConsumerStatefulWidget {
  const TripModeScreen({super.key});

  @override
  ConsumerState<TripModeScreen> createState() => _TripModeScreenState();
}

class _TripModeScreenState extends ConsumerState<TripModeScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(tripModeProvider.notifier).load());
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(tripModeProvider);
    final notifier = ref.read(tripModeProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ride'),
        actions: [
          if (state.outboxCount > 0)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.s4),
              child: _SyncBadge(
                count: state.outboxCount,
                onTap: state.isLoading ? null : notifier.flushOutbox,
              ),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: notifier.load,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.s5,
            AppSpacing.s4,
            AppSpacing.s5,
            AppSpacing.s10,
          ),
          children: [
            _HeroCard(state: state),
            const SizedBox(height: AppSpacing.s5),
            if (state.statusMessage != null) ...[
              _InfoStrip(message: state.statusMessage!),
              const SizedBox(height: AppSpacing.s4),
            ],
            if (!state.hasActiveTrip) ...[
              _StationPicker(
                label: 'Board at',
                icon: Icons.trip_origin,
                stations: state.stations,
                value: state.selectedStartStationId,
                onChanged: (v) { if (v != null) notifier.selectStart(v); },
              ),
              const SizedBox(height: AppSpacing.s3),
              _StationPicker(
                label: 'Get off at',
                icon: Icons.location_on_outlined,
                stations: state.stations,
                value: state.selectedEndStationId,
                onChanged: (v) { if (v != null) notifier.selectEnd(v); },
              ),
              const SizedBox(height: AppSpacing.s5),
            ],
            _RideButton(state: state, notifier: notifier),
            if (!state.hasActiveTrip && state.pointsEarnedThisRide > 0) ...[
              const SizedBox(height: AppSpacing.s5),
              _RideSummaryCard(points: state.pointsEarnedThisRide),
            ],
            const SizedBox(height: AppSpacing.s5),
            _AdaptiveContentSlot(state: state),
          ],
        ),
      ),
    );
  }
}

// ─── Hero card ───────────────────────────────────────────────────────────────

class _HeroCard extends StatelessWidget {
  final TripModeState state;
  const _HeroCard({required this.state});

  String _elapsed() {
    final d = state.elapsed;
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final active = state.hasActiveTrip;
    final trip   = state.activeTrip;

    String? startName;
    if (active && trip != null) {
      final startStation = trip['startStation'] as Map?;
      startName = startStation?['name'] as String? ?? 'Origin';
    }
    final endName = active && state.selectedEndStationId != null
        ? state.stations
            .where((s) => s.id == state.selectedEndStationId)
            .map((s) => s.name)
            .firstOrNull ?? 'Destination'
        : null;

    return Container(
      padding: const EdgeInsets.all(AppSpacing.s6),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: active
              ? [AppColors.mintSuccess, AppColors.metroIndigo]
              : [AppColors.gradientStart, AppColors.gradientEnd],
        ),
        borderRadius: AppRadius.borderRadiusXXL,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                active ? Icons.directions_transit_filled : Icons.route_outlined,
                color: Colors.white,
                size: 32,
              ),
              const Spacer(),
              if (active)
                _TimerBadge(elapsed: _elapsed()),
            ],
          ),
          const SizedBox(height: AppSpacing.s4),
          Text(
            active ? 'You\'re on the metro' : 'Start your commute',
            style: AppTypography.displaySmall.copyWith(color: Colors.white),
          ),
          const SizedBox(height: AppSpacing.s2),
          if (active && startName != null && endName != null)
            _RouteRow(from: startName, to: endName)
          else
            Text(
              'Track your ride, earn points, play games during the commute.',
              style: AppTypography.bodyMedium.copyWith(color: Colors.white70),
            ),
          if (active) ...[
            const SizedBox(height: AppSpacing.s4),
            _ProgressBar(
              remaining: state.remainingMinutes,
              total: ((state.activeTrip?['expectedDurationSeconds'] as num?)
                          ?.toInt() ?? 1200) ~/
                      60,
            ),
          ],
        ],
      ),
    );
  }
}

class _TimerBadge extends StatelessWidget {
  final String elapsed;
  const _TimerBadge({required this.elapsed});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s3,
        vertical: AppSpacing.s2,
      ),
      decoration: BoxDecoration(
        color: Colors.white24,
        borderRadius: AppRadius.borderRadiusL,
      ),
      child: Text(
        elapsed,
        style: AppTypography.labelLarge.copyWith(
          color: Colors.white,
          fontFeatures: [const FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

class _RouteRow extends StatelessWidget {
  final String from;
  final String to;
  const _RouteRow({required this.from, required this.to});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Flexible(
          child: Text(from,
              style: AppTypography.bodyMedium.copyWith(color: Colors.white),
              overflow: TextOverflow.ellipsis),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s2),
          child: Icon(Icons.arrow_forward, color: Colors.white70, size: 16),
        ),
        Flexible(
          child: Text(to,
              style: AppTypography.bodyMedium.copyWith(color: Colors.white),
              overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }
}

class _ProgressBar extends StatelessWidget {
  final int remaining; // minutes
  final int total;     // minutes
  const _ProgressBar({required this.remaining, required this.total});

  @override
  Widget build(BuildContext context) {
    final fraction = total > 0
        ? ((total - remaining) / total).clamp(0.0, 1.0)
        : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: AppRadius.borderRadiusS,
          child: LinearProgressIndicator(
            value: fraction,
            minHeight: 6,
            backgroundColor: Colors.white30,
            valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
          ),
        ),
        const SizedBox(height: AppSpacing.s2),
        Text(
          remaining > 0 ? '$remaining min remaining' : 'Arriving soon',
          style: AppTypography.labelSmall.copyWith(color: Colors.white70),
        ),
      ],
    );
  }
}

// ─── Station picker ───────────────────────────────────────────────────────────

class _StationPicker extends StatelessWidget {
  final String label;
  final IconData icon;
  final List<MetroStation> stations;
  final String? value;
  final ValueChanged<String?> onChanged;

  const _StationPicker({
    required this.label,
    required this.icon,
    required this.stations,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final safeValue = stations.any((s) => s.id == value) ? value : null;
    return DropdownButtonFormField<String>(
      isExpanded: true,
      initialValue: safeValue,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20),
        border: const OutlineInputBorder(borderRadius: AppRadius.borderRadiusL),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s4,
          vertical: AppSpacing.s4,
        ),
      ),
      items: stations
          .map((s) => DropdownMenuItem<String>(
                value: s.id,
                child: Text('${s.name} · ${s.line}',
                    overflow: TextOverflow.ellipsis),
              ))
          .toList(),
      onChanged: stations.isEmpty ? null : onChanged,
    );
  }
}

// ─── Ride button ──────────────────────────────────────────────────────────────

class _RideButton extends StatelessWidget {
  final TripModeState state;
  final TripModeNotifier notifier;
  const _RideButton({required this.state, required this.notifier});

  @override
  Widget build(BuildContext context) {
    final active = state.hasActiveTrip;
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: FilledButton.icon(
        style: FilledButton.styleFrom(
          backgroundColor:
              active ? Theme.of(context).colorScheme.error : null,
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.borderRadiusXL,
          ),
        ),
        onPressed: state.isLoading
            ? null
            : active
                ? notifier.endTrip
                : notifier.startManualTrip,
        icon: state.isLoading
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Icon(active ? Icons.flag_outlined : Icons.train_outlined),
        label: Text(active ? 'End Ride' : 'Start Ride'),
      ),
    );
  }
}

// ─── Ride summary card ────────────────────────────────────────────────────────

class _RideSummaryCard extends StatelessWidget {
  final int points;
  const _RideSummaryCard({required this.points});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.s5),
      decoration: BoxDecoration(
        color: cs.tertiaryContainer,
        borderRadius: AppRadius.borderRadiusXL,
      ),
      child: Row(
        children: [
          const Text('🎉', style: TextStyle(fontSize: 32)),
          const SizedBox(width: AppSpacing.s4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Ride complete!',
                    style: AppTypography.titleMedium
                        .copyWith(color: cs.onTertiaryContainer)),
                Text('+$points pts earned this ride',
                    style: AppTypography.bodyMedium
                        .copyWith(color: cs.onTertiaryContainer)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Adaptive content slot ────────────────────────────────────────────────────

class _AdaptiveContentSlot extends StatelessWidget {
  final TripModeState state;
  const _AdaptiveContentSlot({required this.state});

  @override
  Widget build(BuildContext context) {
    if (!state.hasActiveTrip) {
      return _FeatureHighlights();
    }
    final min = state.remainingMinutes;
    if (min > 20) return _AudioSlot();
    if (min > 8)  return _TriviaSlot();
    if (min > 3)  return _SpinSlot();
    return _StampSlot();
  }
}

class _AudioSlot extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return _ContentCard(
      gradient: [AppColors.metroIndigo, const Color(0xFF7C3AED)],
      icon: '🎧',
      label: 'Long ride',
      title: 'Audio Story',
      body: 'You\'ve got 20+ minutes — perfect for an audio episode.',
      actionLabel: 'Listen now',
      onTap: (ctx) => ctx.push('/audio'),
    );
  }
}

class _TriviaSlot extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return _ContentCard(
      gradient: [AppColors.warmCoral, const Color(0xFFF97316)],
      icon: '🧠',
      label: '8–20 min',
      title: 'Metro Trivia',
      body: 'Quick trivia to keep your mind sharp during the commute.',
      actionLabel: 'Play trivia',
      onTap: (ctx) => ctx.push('/play'),
    );
  }
}

class _SpinSlot extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return _ContentCard(
      gradient: [AppColors.goldPoints, const Color(0xFFEF4444)],
      icon: '🎰',
      label: '3–8 min',
      title: 'Daily Spin',
      body: 'A quick spin to earn bonus points before you arrive.',
      actionLabel: 'Spin now',
      onTap: (ctx) => ctx.push('/play'),
    );
  }
}

class _StampSlot extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return _ContentCard(
      gradient: [AppColors.mintSuccess, const Color(0xFF059669)],
      icon: '📍',
      label: 'Almost there',
      title: 'Station Stamp',
      body: 'Collect your station stamp as you arrive.',
      actionLabel: 'View stamps',
      onTap: (ctx) => ctx.push('/stamps'),
    );
  }
}

class _FeatureHighlights extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.s5),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: AppRadius.borderRadiusXXL,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('While you ride',
              style: AppTypography.titleMedium
                  .copyWith(color: cs.onSurface)),
          const SizedBox(height: AppSpacing.s2),
          Text(
            'Start a ride to unlock games, audio stories, and station stamps matched to your commute length.',
            style: AppTypography.bodyMedium
                .copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: AppSpacing.s4),
          Wrap(
            spacing: AppSpacing.s2,
            runSpacing: AppSpacing.s2,
            children: const [
              _Pill(label: '🎧 Audio stories'),
              _Pill(label: '🧠 Trivia'),
              _Pill(label: '🎰 Daily spin'),
              _Pill(label: '📍 Stamps'),
            ],
          ),
        ],
      ),
    );
  }
}

class _ContentCard extends StatelessWidget {
  final List<Color> gradient;
  final String icon;
  final String label;
  final String title;
  final String body;
  final String actionLabel;
  final void Function(BuildContext) onTap;

  const _ContentCard({
    required this.gradient,
    required this.icon,
    required this.label,
    required this.title,
    required this.body,
    required this.actionLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.s5),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: gradient,
        ),
        borderRadius: AppRadius.borderRadiusXXL,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(icon, style: const TextStyle(fontSize: 28)),
              const SizedBox(width: AppSpacing.s3),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.s3,
                  vertical: AppSpacing.s1,
                ),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: AppRadius.borderRadiusM,
                ),
                child: Text(label,
                    style: AppTypography.labelSmall
                        .copyWith(color: Colors.white)),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s3),
          Text(title,
              style:
                  AppTypography.titleLarge.copyWith(color: Colors.white)),
          const SizedBox(height: AppSpacing.s2),
          Text(body,
              style: AppTypography.bodyMedium
                  .copyWith(color: Colors.white70)),
          const SizedBox(height: AppSpacing.s4),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white,
              side: const BorderSide(color: Colors.white54),
              shape: RoundedRectangleBorder(
                borderRadius: AppRadius.borderRadiusL,
              ),
            ),
            onPressed: () => onTap(context),
            child: Text(actionLabel),
          ),
        ],
      ),
    );
  }
}

// ─── Sync badge ───────────────────────────────────────────────────────────────

class _SyncBadge extends StatelessWidget {
  final int count;
  final VoidCallback? onTap;
  const _SyncBadge({required this.count, this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.borderRadiusM,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s3,
          vertical: AppSpacing.s2,
        ),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.errorContainer,
          borderRadius: AppRadius.borderRadiusM,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.sync,
                size: 16,
                color: Theme.of(context).colorScheme.onErrorContainer),
            const SizedBox(width: AppSpacing.s1),
            Text(
              '$count',
              style: AppTypography.labelMedium.copyWith(
                color: Theme.of(context).colorScheme.onErrorContainer,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Info strip ───────────────────────────────────────────────────────────────

class _InfoStrip extends StatelessWidget {
  final String message;
  const _InfoStrip({required this.message});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s4,
        vertical: AppSpacing.s3,
      ),
      decoration: BoxDecoration(
        color: cs.primaryContainer,
        borderRadius: AppRadius.borderRadiusL,
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 16, color: cs.onPrimaryContainer),
          const SizedBox(width: AppSpacing.s2),
          Expanded(
            child: Text(message,
                style: AppTypography.bodySmall
                    .copyWith(color: cs.onPrimaryContainer)),
          ),
        ],
      ),
    );
  }
}

// ─── Pill chip ────────────────────────────────────────────────────────────────

class _Pill extends StatelessWidget {
  final String label;
  const _Pill({required this.label});

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(label, style: AppTypography.labelSmall),
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
    );
  }
}

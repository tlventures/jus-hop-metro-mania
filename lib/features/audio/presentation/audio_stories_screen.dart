

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:metrosafar/design_system/components/state_views.dart';
import 'package:metrosafar/design_system/tokens/colors.dart';
import 'package:metrosafar/design_system/tokens/radius.dart';
import 'package:metrosafar/design_system/tokens/spacing.dart';
import 'package:metrosafar/design_system/tokens/typography.dart';
import 'package:metrosafar/features/audio/application/episodes_provider.dart';
import 'package:metrosafar/services/audio_player_service.dart';

class AudioStoriesScreen extends ConsumerWidget {
  const AudioStoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final episodes = ref.watch(episodesProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Metro Tales')),
      body: episodes.when(
        data: (items) => Column(
          children: [
            // Now-playing bar (always visible if something is loaded)
            const _NowPlayingBar(),
            Expanded(
              child: RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(episodesProvider);
                  await ref.read(episodesProvider.future);
                },
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.all(AppSpacing.s6),
                  children: [
                    _HeroBanner(),
                    const SizedBox(height: AppSpacing.s6),
                    ...items.map((ep) => _EpisodeCard(episode: ep)),
                    if (items.isEmpty)
                      Text(
                        'Pilot episodes will appear after backend sync.',
                        style: AppTypography.bodyMedium
                            .copyWith(color: colorScheme.onSurfaceVariant),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => AppErrorState(
          title: 'Could not load episodes',
          message: 'Check your connection and try again.',
          onRetry: () => ref.invalidate(episodesProvider),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Hero banner
// ---------------------------------------------------------------------------

class _HeroBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.s6),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0F766E), AppColors.metroIndigo],
        ),
        borderRadius: AppRadius.borderRadiusXXL,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Commute-length audio',
            style: AppTypography.displaySmall.copyWith(color: Colors.white),
          ),
          const SizedBox(height: AppSpacing.s2),
          Text(
            'Stories timed for your ride. Resume exactly where you left off, on any device.',
            style: AppTypography.bodyMedium
                .copyWith(color: Colors.white70),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Now-playing bar
// ---------------------------------------------------------------------------

class _NowPlayingBar extends ConsumerWidget {
  const _NowPlayingBar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final handler = ref.watch(audioHandlerProvider);
    return StreamBuilder<MediaItem?>(
      stream: handler.mediaItem,
      builder: (context, snapshot) {
        final item = snapshot.data;
        if (item == null) return const SizedBox.shrink();

        final colorScheme = Theme.of(context).colorScheme;
        final service = ref.read(audioPlayerServiceProvider);

        return Container(
          color: colorScheme.primaryContainer,
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s4,
            vertical: AppSpacing.s2,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.labelMedium.copyWith(
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                    StreamBuilder<Duration>(
                      stream: handler.positionStream,
                      builder: (context, posSnap) {
                        final pos = posSnap.data ?? Duration.zero;
                        final dur = item.duration ?? Duration.zero;
                        return _PositionRow(position: pos, duration: dur);
                      },
                    ),
                  ],
                ),
              ),
              StreamBuilder<PlayerState>(
                stream: handler.playerStateStream,
                builder: (context, stateSnap) {
                  final playing =
                      stateSnap.data?.playing ?? false;
                  return Row(
                    children: [
                      IconButton(
                        icon: Icon(
                          playing ? Icons.pause : Icons.play_arrow,
                          color: colorScheme.onPrimaryContainer,
                        ),
                        onPressed: service.togglePlayPause,
                      ),
                      IconButton(
                        icon: Icon(
                          Icons.stop,
                          color: colorScheme.onPrimaryContainer,
                        ),
                        onPressed: service.stop,
                      ),
                    ],
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PositionRow extends StatelessWidget {
  final Duration position;
  final Duration duration;
  const _PositionRow({required this.position, required this.duration});

  String _fmt(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final ratio = duration.inSeconds > 0
        ? (position.inSeconds / duration.inSeconds).clamp(0.0, 1.0)
        : 0.0;
    return Row(
      children: [
        Text(
          '${_fmt(position)} / ${_fmt(duration)}',
          style: AppTypography.labelSmall
              .copyWith(color: colorScheme.onPrimaryContainer.withValues(alpha: 0.7)),
        ),
        const SizedBox(width: AppSpacing.s2),
        Expanded(
          child: LinearProgressIndicator(
            value: ratio,
            backgroundColor:
                colorScheme.onPrimaryContainer.withValues(alpha: 0.2),
            color: colorScheme.onPrimaryContainer,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Episode card
// ---------------------------------------------------------------------------

class _EpisodeCard extends ConsumerWidget {
  final Map<String, dynamic> episode;
  const _EpisodeCard({required this.episode});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;
    final handler = ref.watch(audioHandlerProvider);
    final service = ref.read(audioPlayerServiceProvider);
    final episodeId = episode['id'] as String;
    final duration =
        ((episode['durationSeconds'] as num? ?? 0) / 60).round();

    return StreamBuilder<MediaItem?>(
      stream: handler.mediaItem,
      builder: (context, snapshot) {
        final isCurrentEpisode = snapshot.data?.id == episodeId;

        return Container(
          margin: const EdgeInsets.only(bottom: AppSpacing.s4),
          padding: const EdgeInsets.all(AppSpacing.s4),
          decoration: BoxDecoration(
            color: isCurrentEpisode
                ? colorScheme.primaryContainer.withValues(alpha: 0.4)
                : colorScheme.surfaceContainer,
            borderRadius: AppRadius.borderRadiusXL,
            border: isCurrentEpisode
                ? Border.all(color: colorScheme.primary, width: 1.5)
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Art thumbnail placeholder
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: const Color(0xFF0F766E).withValues(alpha: 0.15),
                      borderRadius: AppRadius.borderRadiusM,
                    ),
                    child: const Icon(
                      Icons.headphones,
                      color: Color(0xFF0F766E),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          episode['title'] as String? ?? 'Metro Episode',
                          style: AppTypography.titleSmall.copyWith(
                            color: colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.s1),
                        Text(
                          '$duration min • ${episode['synopsis'] ?? ''}',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.bodySmall.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.s3),
              // Chapters
              if (episode['chapters'] != null)
                _ChapterList(chapters: episode['chapters'] as List<dynamic>),
              const SizedBox(height: AppSpacing.s3),
              // Controls
              Row(
                children: [
                  if (!isCurrentEpisode)
                    FilledButton.icon(
                      onPressed: () => service.play(episode: episode),
                      icon: const Icon(Icons.play_arrow, size: 18),
                      label: const Text('Play'),
                    )
                  else
                    StreamBuilder<PlayerState>(
                      stream: handler.playerStateStream,
                      builder: (context, stateSnap) {
                        final playing =
                            stateSnap.data?.playing ?? false;
                        return FilledButton.icon(
                          onPressed: service.togglePlayPause,
                          icon: Icon(
                            playing ? Icons.pause : Icons.play_arrow,
                            size: 18,
                          ),
                          label: Text(playing ? 'Pause' : 'Resume'),
                        );
                      },
                    ),
                  const SizedBox(width: AppSpacing.s3),
                  if (episode['isPremium'] == true)
                    Chip(
                      label: const Text('Premium'),
                      backgroundColor:
                          AppColors.goldPoints.withValues(alpha: 0.15),
                      labelStyle: AppTypography.labelSmall.copyWith(
                        color: AppColors.goldPoints,
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ChapterList extends StatelessWidget {
  final List<dynamic> chapters;
  const _ChapterList({required this.chapters});

  String _fmt(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: AppSpacing.s2,
      runSpacing: AppSpacing.s1,
      children: chapters.map((c) {
        final chapter = Map<String, dynamic>.from(c as Map);
        final title = chapter['title'] as String? ?? '';
        final start = (chapter['startSeconds'] as num?)?.toInt() ?? 0;
        return Chip(
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          padding: EdgeInsets.zero,
          label: Text(
            '$title ${_fmt(start)}',
            style: AppTypography.labelSmall
                .copyWith(color: colorScheme.onSurfaceVariant),
          ),
          backgroundColor: colorScheme.surface,
        );
      }).toList(),
    );
  }
}

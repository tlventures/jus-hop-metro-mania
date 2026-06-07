import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import 'backend_service.dart';
import 'telemetry.dart';

// ---------------------------------------------------------------------------
// AudioHandler — bridges just_audio to audio_service lock-screen controls
// ---------------------------------------------------------------------------

class MetroAudioHandler extends BaseAudioHandler with SeekHandler {
  final AudioPlayer _player = AudioPlayer();

  MetroAudioHandler() {
    _player.playbackEventStream.listen(_broadcastState);
    _player.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) {
        stop();
      }
    });
  }

  Future<void> loadEpisode({
    required String url,
    required MediaItem item,
    int startPositionSeconds = 0,
  }) async {
    mediaItem.add(item);
    await _player.setUrl(url);
    if (startPositionSeconds > 0) {
      await _player.seek(Duration(seconds: startPositionSeconds));
    }
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() async {
    await _player.stop();
    playbackState.add(playbackState.value.copyWith(
      controls: [],
      processingState: AudioProcessingState.idle,
    ));
  }

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> skipToNext() async {}

  @override
  Future<void> skipToPrevious() async {}

  void _broadcastState(PlaybackEvent event) {
    final playing = _player.playing;
    playbackState.add(playbackState.value.copyWith(
      controls: [
        MediaControl.rewind,
        playing ? MediaControl.pause : MediaControl.play,
        MediaControl.fastForward,
        MediaControl.stop,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.rewind,
        MediaAction.fastForward,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState: switch (_player.processingState) {
        ProcessingState.idle => AudioProcessingState.idle,
        ProcessingState.loading => AudioProcessingState.loading,
        ProcessingState.buffering => AudioProcessingState.buffering,
        ProcessingState.ready => AudioProcessingState.ready,
        ProcessingState.completed => AudioProcessingState.completed,
      },
      playing: playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
      queueIndex: event.currentIndex,
    ));
  }

  AudioPlayer get player => _player;

  Duration get position => _player.position;
  Duration get duration => _player.duration ?? Duration.zero;
  bool get playing => _player.playing;

  Stream<Duration> get positionStream => _player.positionStream;
  Stream<PlayerState> get playerStateStream => _player.playerStateStream;
}

// ---------------------------------------------------------------------------
// AudioPlayerService — higher level, handles position sync
// ---------------------------------------------------------------------------

class AudioPlayerService {
  final MetroAudioHandler _handler;
  final BackendService _backend;

  String? _currentEpisodeId;
  Timer? _syncTimer;

  AudioPlayerService(this._handler, this._backend);

  MetroAudioHandler get handler => _handler;

  Future<void> play({
    required Map<String, dynamic> episode,
  }) async {
    final episodeId = episode['id'] as String;
    final url = episode['audioUrl'] as String? ?? '';
    final title = episode['title'] as String? ?? 'Metro Tales';
    final artUrl = episode['artUrl'] as String?;
    final durationSecs = (episode['durationSeconds'] as num?)?.toInt() ?? 0;

    // Fetch saved position for cross-device resume.
    int startAt = 0;
    try {
      final pos = await _backend.getEpisodePosition(episodeId);
      startAt = (pos['positionSeconds'] as num?)?.toInt() ?? 0;
      if (startAt >= durationSecs - 5) startAt = 0; // episode effectively done
    } catch (e, st) {
      Telemetry.recordNonFatal(e, st, reason: 'episode_position_fetch');
    }

    final item = MediaItem(
      id: episodeId,
      title: title,
      duration: Duration(seconds: durationSecs),
      artUri: artUrl != null ? Uri.tryParse(artUrl) : null,
    );

    await _handler.loadEpisode(url: url, item: item, startPositionSeconds: startAt);
    await _handler.play();

    _currentEpisodeId = episodeId;
    _startSyncTimer();
  }

  Future<void> togglePlayPause() async {
    if (_handler.playing) {
      await _handler.pause();
    } else {
      await _handler.play();
    }
  }

  Future<void> seek(Duration position) => _handler.seek(position);

  Future<void> stop() async {
    _syncTimer?.cancel();
    await _syncCurrentPosition(completed: false);
    await _handler.stop();
    _currentEpisodeId = null;
  }

  void _startSyncTimer() {
    _syncTimer?.cancel();
    // Sync position every 10 seconds.
    _syncTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _syncCurrentPosition(completed: false);
    });
  }

  Future<void> _syncCurrentPosition({required bool completed}) async {
    final id = _currentEpisodeId;
    if (id == null) return;
    final posSeconds = _handler.position.inSeconds;
    if (posSeconds <= 0) return;
    try {
      await _backend.updateEpisodePosition(
        episodeId: id,
        positionSeconds: posSeconds,
        completed: completed,
      );
    } catch (e) {
      debugPrint('[AudioPlayerService] sync error: $e');
    }
  }

  void dispose() {
    _syncTimer?.cancel();
    _handler.stop();
  }
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

// Initialized in main() via AudioService.init() and overridden on ProviderScope.
// Falls back to a standalone handler when running in test/without full audio service.
final audioHandlerProvider = Provider<MetroAudioHandler>((ref) {
  final handler = MetroAudioHandler();
  ref.onDispose(handler.stop);
  return handler;
});

final audioPlayerServiceProvider = Provider<AudioPlayerService>((ref) {
  final handler = ref.watch(audioHandlerProvider);
  final service = AudioPlayerService(handler, BackendService());
  ref.onDispose(service.dispose);
  return service;
});

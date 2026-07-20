import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_models/shared_models.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import 'session_controller.dart';

class PlaybackController extends StateNotifier<AsyncValue<void>> {
  PlaybackController(this.ref)
      : youtubeController = YoutubePlayerController(
          params: const YoutubePlayerParams(
            mute: false,
            showControls: true,
            loop: false,
            strictRelatedVideos: true,
            enableCaption: false,
            showFullscreenButton: false,
          ),
        ),
        super(const AsyncValue.data(null)) {
    ref.listen<HostSessionState>(hostSessionProvider, (previous, next) {
      if (previous?.connected == true && !next.connected) {
        unawaited(stopPlayback(broadcast: false));
        return;
      }
      if (_playlistOrderChanged(previous?.state, next.state)) {
        _syncIndexToPlaylist(next.state);
      }
    });
    _init();
  }

  final Ref ref;
  final YoutubePlayerController youtubeController;

  /// Host playback always uses the official YouTube IFrame Player API.
  bool get usesYoutubeIframe => true;

  StreamSubscription<YoutubePlayerValue>? _youtubeSub;
  Timer? _youtubePositionTimer;
  int _currentIndex = -1;
  int _retryCount = 0;
  String? _activeTrackId;
  /// Invalidates overlapping playIndex/next/previous calls.
  int _playEpoch = 0;
  static const _maxRetries = 1;

  /// Playlist index currently loaded into the player (−1 if none).
  int get currentIndex => _currentIndex;

  /// Track id loaded into the active player, if any.
  String? get activeTrackId => _activeTrackId;

  /// Resolves the track that should be shown in the Control UI.
  Track? get displayTrack {
    final hostState = ref.read(hostSessionProvider).state;
    if (_activeTrackId != null) {
      for (final track in hostState.playlist) {
        if (track.id == _activeTrackId) return track;
      }
    }
    if (_currentIndex >= 0 && _currentIndex < hostState.playlist.length) {
      return hostState.playlist[_currentIndex];
    }
    return hostState.nowPlaying;
  }

  void _syncNowPlayingToEngine({bool broadcast = true}) {
    final hostState = ref.read(hostSessionProvider).state;
    final index = _resolvePlaybackIndex(hostState);
    if (index < 0 || index >= hostState.playlist.length) return;
    if (hostState.nowPlayingIndex == index) {
      return;
    }
    ref.read(hostSessionProvider.notifier).updatePlayback(
          nowPlayingIndex: index,
          broadcast: broadcast,
        );
  }

  /// Finds the playing track in the current playlist order.
  int _resolvePlaybackIndex(HostState hostState) {
    if (_activeTrackId != null) {
      final byId =
          hostState.playlist.indexWhere((track) => track.id == _activeTrackId);
      if (byId >= 0) {
        _currentIndex = byId;
        return byId;
      }
    }
    if (_currentIndex >= 0 && _currentIndex < hostState.playlist.length) {
      return _currentIndex;
    }
    final sessionIndex = hostState.nowPlayingIndex;
    if (sessionIndex >= 0 && sessionIndex < hostState.playlist.length) {
      _currentIndex = sessionIndex;
      return sessionIndex;
    }
    return -1;
  }

  bool _playlistOrderChanged(HostState? previous, HostState next) {
    if (previous == null) return true;
    final before = previous.playlist;
    final after = next.playlist;
    if (identical(before, after)) return false;
    if (before.length != after.length) return true;
    for (var i = 0; i < before.length; i++) {
      if (before[i].id != after[i].id) return true;
    }
    return false;
  }

  void _syncIndexToPlaylist(HostState hostState) {
    if (_activeTrackId == null || hostState.playlist.isEmpty) return;
    final index =
        hostState.playlist.indexWhere((track) => track.id == _activeTrackId);
    if (index < 0) return;
    if (_currentIndex != index) {
      _currentIndex = index;
    }
    if (hostState.nowPlayingIndex != index) {
      ref.read(hostSessionProvider.notifier).updatePlayback(
            nowPlayingIndex: index,
            broadcast: true,
          );
    }
  }

  Future<void> _init() async {
    _youtubeSub = youtubeController.stream.listen((value) {
      final isPlaying = value.playerState == PlayerState.playing;
      ref.read(hostSessionProvider.notifier).updatePlayback(
            isPlaying: isPlaying,
          );

      if (value.playerState == PlayerState.ended) {
        _onTrackFinished();
      }
    });

    _youtubePositionTimer = Timer.periodic(const Duration(seconds: 1), (_) async {
      try {
        final seconds = await youtubeController.currentTime;
        final duration = await youtubeController.duration;
        // Broadcast so connectors (including web) stay in sync while music plays.
        ref.read(hostSessionProvider.notifier).updatePlayback(
              positionMs: (seconds * 1000).round(),
              durationMs: (duration * 1000).round(),
              broadcast: true,
            );
        _syncNowPlayingToEngine(broadcast: true);
      } catch (_) {}
    });
  }

  Future<void> _pauseYoutubeIfNeeded() async {
    try {
      await youtubeController.pauseVideo().timeout(const Duration(milliseconds: 400));
      await youtubeController.mute().timeout(const Duration(milliseconds: 400));
    } catch (_) {}
  }

  /// Stops playback and clears the loaded track. Only allowed while a host
  /// session is connected for live control; still safe to call when leaving.
  Future<void> stopPlayback({bool broadcast = true}) async {
    _playEpoch++;
    _currentIndex = -1;
    _activeTrackId = null;
    _retryCount = 0;

    await _pauseYoutubeIfNeeded();
    try {
      await youtubeController.stopVideo().timeout(const Duration(milliseconds: 400));
    } catch (_) {}

    final host = ref.read(hostSessionProvider);
    if (host.connected) {
      try {
        ref.read(hostSessionProvider.notifier).updatePlayback(
              isPlaying: false,
              positionMs: 0,
              broadcast: broadcast,
            );
      } catch (_) {}
    }

    state = const AsyncValue.data(null);
  }

  bool get _sessionAllowsPlayback =>
      ref.read(hostSessionProvider).connected;

  void _onTrackFinished() {
    if (!_sessionAllowsPlayback) return;
    final settings = ref.read(hostSessionProvider).state.settings;
    if (settings.autoPlaylistAdvance) {
      unawaited(next());
    } else {
      ref.read(hostSessionProvider.notifier).updatePlayback(isPlaying: false);
    }
  }

  Future<void> playIndex(int index, {List<Track>? playlist}) async {
    if (!_sessionAllowsPlayback) return;
    final hostState = ref.read(hostSessionProvider).state;
    final tracks = playlist ?? hostState.playlist;
    if (index < 0 || index >= tracks.length) return;

    final previousIndex = _currentIndex;
    final previousTrackId = _activeTrackId;
    final epoch = ++_playEpoch;
    final track = tracks[index];

    _currentIndex = index;
    _activeTrackId = track.id;
    ref.read(hostSessionProvider.notifier).updatePlayback(
          nowPlayingIndex: index,
          isPlaying: true,
          positionMs: 0,
        );

    state = const AsyncValue.loading();
    try {
      debugPrint('playIndex($index) id=${track.id} iframe=true epoch=$epoch');

      if (epoch != _playEpoch) return;
      await youtubeController.unMute();
      await youtubeController.cueVideoById(videoId: track.id);
      await Future<void>.delayed(const Duration(milliseconds: 150));
      if (epoch != _playEpoch) return;
      await youtubeController.playVideo();

      if (epoch != _playEpoch) return;
      _retryCount = 0;
      state = const AsyncValue.data(null);
    } catch (error, stack) {
      if (epoch != _playEpoch) return;
      debugPrint('Playback error: $error');
      _currentIndex = previousIndex;
      _activeTrackId = previousTrackId;
      state = AsyncValue.error(error, stack);
      if (_retryCount < _maxRetries) {
        _retryCount++;
        await Future<void>.delayed(const Duration(seconds: 1));
        if (epoch != _playEpoch) return;
        await playIndex(index, playlist: tracks);
      } else {
        _retryCount = 0;
        ref.read(hostSessionProvider.notifier).updatePlayback(
              nowPlayingIndex: previousIndex >= 0 ? previousIndex : index,
              isPlaying: false,
            );
      }
    } finally {
      if (epoch == _playEpoch && state.isLoading) {
        state = const AsyncValue.data(null);
      }
    }
  }

  Future<void> togglePlayPause() async {
    if (!_sessionAllowsPlayback) {
      await stopPlayback();
      return;
    }
    final hostState = ref.read(hostSessionProvider).state;
    final playIndexTarget = hostState.nowPlayingIndex >= 0
        ? hostState.nowPlayingIndex
        : 0;

    if (state.isLoading) {
      state = const AsyncValue.data(null);
    }

    if (_currentIndex == -1 && hostState.playlist.isNotEmpty) {
      await playIndex(playIndexTarget);
      return;
    }

    final ytState = youtubeController.value.playerState;
    if (ytState == PlayerState.playing || hostState.isPlaying) {
      await youtubeController.pauseVideo();
      ref.read(hostSessionProvider.notifier).updatePlayback(isPlaying: false);
    } else if (ytState == PlayerState.paused || ytState == PlayerState.cued) {
      await youtubeController.playVideo();
      ref.read(hostSessionProvider.notifier).updatePlayback(isPlaying: true);
    } else if (hostState.playlist.isNotEmpty) {
      await playIndex(playIndexTarget.clamp(0, hostState.playlist.length - 1));
    }
  }

  Future<void> next() async {
    if (!_sessionAllowsPlayback) return;
    final hostState = ref.read(hostSessionProvider).state;
    if (hostState.playlist.isEmpty) return;

    final current = _resolvePlaybackIndex(hostState);
    if (current < 0) {
      await playIndex(0);
      return;
    }

    final nextIndex = current + 1;
    if (nextIndex >= hostState.playlist.length) {
      await youtubeController.seekTo(seconds: 0);
      await youtubeController.playVideo();
      return;
    }
    await playIndex(nextIndex);
  }

  Future<void> previous() async {
    if (!_sessionAllowsPlayback) return;
    final hostState = ref.read(hostSessionProvider).state;
    if (hostState.playlist.isEmpty) return;

    try {
      final seconds = await youtubeController.currentTime;
      if (seconds > 3) {
        await youtubeController.seekTo(seconds: 0);
        return;
      }
    } catch (_) {}

    final current = _resolvePlaybackIndex(hostState);
    if (current <= 0) {
      await playIndex(0);
      return;
    }
    await playIndex(current - 1);
  }

  Future<void> seek(Duration position) async {
    await youtubeController.seekTo(seconds: position.inMilliseconds / 1000);
  }

  @override
  void dispose() {
    _playEpoch++;
    _youtubeSub?.cancel();
    _youtubePositionTimer?.cancel();
    youtubeController.close();
    super.dispose();
  }
}

final playbackProvider =
    StateNotifierProvider<PlaybackController, AsyncValue<void>>((ref) {
  return PlaybackController(ref);
});

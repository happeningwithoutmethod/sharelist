import { useEffect, useRef } from 'react';
import { youtubeIdFromTrack, useHostStore } from '../store/hostSession';

declare global {
  interface Window {
    YT?: {
      Player: new (
        el: HTMLElement | string,
        opts: Record<string, unknown>,
      ) => YtPlayer;
      PlayerState: { PLAYING: number; PAUSED: number; ENDED: number };
    };
    onYouTubeIframeAPIReady?: () => void;
  }
}

interface YtPlayer {
  destroy: () => void;
  cueVideoById: (id: string) => void;
  loadVideoById: (id: string) => void;
  playVideo: () => void;
  pauseVideo: () => void;
  seekTo: (seconds: number, allowSeek: boolean) => void;
  getCurrentTime: () => number;
  getDuration: () => number;
  getPlayerState: () => number;
}

let apiLoading: Promise<void> | null = null;

function loadYoutubeApi(): Promise<void> {
  if (window.YT?.Player) return Promise.resolve();
  if (apiLoading) return apiLoading;
  apiLoading = new Promise((resolve) => {
    const previous = window.onYouTubeIframeAPIReady;
    window.onYouTubeIframeAPIReady = () => {
      previous?.();
      resolve();
    };
    const script = document.createElement('script');
    script.src = 'https://www.youtube.com/iframe_api';
    document.head.appendChild(script);
  });
  return apiLoading;
}

export function YoutubePlayer({ compact = false }: { compact?: boolean }) {
  const mountRef = useRef<HTMLDivElement>(null);
  const playerRef = useRef<YtPlayer | null>(null);
  const lastVideoRef = useRef<string | null>(null);
  const state = useHostStore((s) => s.state);
  const updatePlayback = useHostStore((s) => s.updatePlayback);
  const playIndex = useHostStore((s) => s.playIndex);

  const track =
    state.nowPlayingIndex >= 0 ? state.playlist[state.nowPlayingIndex] : null;
  const videoId = track ? youtubeIdFromTrack(track) : null;

  useEffect(() => {
    let cancelled = false;
    void (async () => {
      await loadYoutubeApi();
      if (cancelled || !mountRef.current || !window.YT) return;
      if (playerRef.current) return;
      playerRef.current = new window.YT.Player(mountRef.current, {
        height: compact ? '180' : '360',
        width: '100%',
        playerVars: {
          rel: 0,
          modestbranding: 1,
          playsinline: 1,
        },
        events: {
          onStateChange: (event: { data: number }) => {
            const YT = window.YT!;
            if (event.data === YT.PlayerState.PLAYING) {
              updatePlayback({ isPlaying: true });
            } else if (event.data === YT.PlayerState.PAUSED) {
              updatePlayback({ isPlaying: false });
            } else if (event.data === YT.PlayerState.ENDED) {
              const { state: hostState } = useHostStore.getState();
              if (!hostState.settings.autoPlaylistAdvance) {
                updatePlayback({ isPlaying: false });
                return;
              }
              const next = hostState.nowPlayingIndex + 1;
              if (next < hostState.playlist.length) playIndex(next);
              else updatePlayback({ isPlaying: false });
            }
          },
        },
      });
    })();
    return () => {
      cancelled = true;
    };
  }, [compact, playIndex, updatePlayback]);

  useEffect(() => {
    const player = playerRef.current;
    if (!player || !videoId) return;
    if (lastVideoRef.current === videoId) {
      const playing = player.getPlayerState() === window.YT!.PlayerState.PLAYING;
      if (state.isPlaying && !playing) player.playVideo();
      if (!state.isPlaying && playing) player.pauseVideo();
      return;
    }
    lastVideoRef.current = videoId;
    if (state.isPlaying) player.loadVideoById(videoId);
    else player.cueVideoById(videoId);
  }, [videoId, state.isPlaying]);

  useEffect(() => {
    const timer = setInterval(() => {
      const player = playerRef.current;
      if (!player || !videoId) return;
      try {
        const positionMs = Math.round(player.getCurrentTime() * 1000);
        const durationMs = Math.round(player.getDuration() * 1000);
        updatePlayback({ positionMs, durationMs });
      } catch {
        // player not ready
      }
    }, 1000);
    return () => clearInterval(timer);
  }, [videoId, updatePlayback]);

  return (
    <div className={`yt-wrap ${compact ? 'compact' : ''}`}>
      <div ref={mountRef} />
      {!track && <p className="muted center">Add a song to start playback</p>}
    </div>
  );
}

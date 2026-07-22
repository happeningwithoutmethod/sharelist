import { useEffect, useRef } from 'react';
import { youtubeIdFromTrack, useHostStore } from '../store/hostSession';

declare global {
  interface Window {
    YT?: {
      Player: new (
        el: HTMLElement | string,
        opts: Record<string, unknown>,
      ) => YtPlayer;
      PlayerState: { PLAYING: number; PAUSED: number; ENDED: number; CUED: number };
      loaded?: number;
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
    const done = () => resolve();
    const previous = window.onYouTubeIframeAPIReady;
    window.onYouTubeIframeAPIReady = () => {
      previous?.();
      done();
    };
    if (!document.querySelector('script[src="https://www.youtube.com/iframe_api"]')) {
      const script = document.createElement('script');
      script.src = 'https://www.youtube.com/iframe_api';
      document.head.appendChild(script);
    }
    // API may already be mid-load; poll in case the callback already fired.
    const start = Date.now();
    const poll = () => {
      if (window.YT?.Player) {
        done();
        return;
      }
      if (Date.now() - start > 15_000) return;
      requestAnimationFrame(poll);
    };
    poll();
  });
  return apiLoading;
}

function safePlayerState(player: YtPlayer): number | null {
  try {
    return player.getPlayerState();
  } catch {
    return null;
  }
}

export function YoutubePlayer({ compact = false }: { compact?: boolean }) {
  const hostRef = useRef<HTMLDivElement>(null);
  const playerRef = useRef<YtPlayer | null>(null);
  const readyRef = useRef(false);
  const lastVideoRef = useRef<string | null>(null);
  const desiredRef = useRef<{ videoId: string | null; isPlaying: boolean }>({
    videoId: null,
    isPlaying: false,
  });

  const nowPlayingIndex = useHostStore((s) => s.state.nowPlayingIndex);
  const playlist = useHostStore((s) => s.state.playlist);
  const isPlaying = useHostStore((s) => s.state.isPlaying);
  const updatePlayback = useHostStore((s) => s.updatePlayback);
  const playIndex = useHostStore((s) => s.playIndex);

  const track =
    nowPlayingIndex >= 0 && nowPlayingIndex < playlist.length
      ? playlist[nowPlayingIndex]
      : null;
  const videoId = track ? youtubeIdFromTrack(track) : null;

  desiredRef.current = { videoId, isPlaying };

  const applyDesired = (player: YtPlayer) => {
    const desired = desiredRef.current;
    if (!desired.videoId) return;

    const YT = window.YT;
    if (!YT) return;

    if (lastVideoRef.current !== desired.videoId) {
      lastVideoRef.current = desired.videoId;
      try {
        if (desired.isPlaying) player.loadVideoById(desired.videoId);
        else player.cueVideoById(desired.videoId);
      } catch {
        // not ready yet
      }
      return;
    }

    const current = safePlayerState(player);
    if (current == null) return;
    try {
      if (desired.isPlaying && current !== YT.PlayerState.PLAYING) {
        player.playVideo();
      } else if (!desired.isPlaying && current === YT.PlayerState.PLAYING) {
        player.pauseVideo();
      }
    } catch {
      // ignore
    }
  };

  useEffect(() => {
    let cancelled = false;
    const host = hostRef.current;
    if (!host) return;

    void (async () => {
      await loadYoutubeApi();
      if (cancelled || !hostRef.current || !window.YT?.Player) return;

      // Tear down any previous instance tied to this mount.
      if (playerRef.current) {
        try {
          playerRef.current.destroy();
        } catch {
          // ignore
        }
        playerRef.current = null;
        readyRef.current = false;
      }

      const mount = document.createElement('div');
      hostRef.current.innerHTML = '';
      hostRef.current.appendChild(mount);

      const player = new window.YT.Player(mount, {
        height: '100%',
        width: '100%',
        playerVars: {
          rel: 0,
          modestbranding: 1,
          playsinline: 1,
          enablejsapi: 1,
          origin: window.location.origin,
        },
        events: {
          onReady: (event: { target: YtPlayer }) => {
            if (cancelled) return;
            playerRef.current = event.target;
            readyRef.current = true;
            applyDesired(event.target);
          },
          onError: (event: { data: number }) => {
            console.warn('YouTube player error', event.data);
          },
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
      // Constructor returns before ready; keep a soft ref for destroy.
      playerRef.current = player;
    })();

    return () => {
      cancelled = true;
      readyRef.current = false;
      lastVideoRef.current = null;
      const player = playerRef.current;
      playerRef.current = null;
      if (player) {
        try {
          player.destroy();
        } catch {
          // ignore
        }
      }
      if (host) host.innerHTML = '';
    };
    // Mount once per component instance; size is CSS-driven.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => {
    if (!readyRef.current || !playerRef.current) return;
    applyDesired(playerRef.current);
  }, [videoId, isPlaying]);

  useEffect(() => {
    const timer = setInterval(() => {
      const player = playerRef.current;
      if (!readyRef.current || !player || !videoId) return;
      try {
        const positionMs = Math.round(player.getCurrentTime() * 1000);
        const durationMs = Math.round(player.getDuration() * 1000);
        if (Number.isFinite(positionMs) && Number.isFinite(durationMs)) {
          updatePlayback({ positionMs, durationMs });
        }
      } catch {
        // player not ready
      }
    }, 1000);
    return () => clearInterval(timer);
  }, [videoId, updatePlayback]);

  return (
    <div className={`yt-wrap ${compact ? 'compact' : ''}`}>
      <div className="yt-host" ref={hostRef} />
      {!track && <p className="muted center yt-empty">Add a song to start playback</p>}
    </div>
  );
}

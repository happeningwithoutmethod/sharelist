import { useEffect, useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { searchMusic } from '../api/relay';
import { BottomNav } from '../components/BottomNav';
import { TrackRow, formatMs } from '../components/TrackRow';
import { trackArtist, trackTitle } from '../lib/trackText';
import type { Track } from '../protocol/types';
import { useConnectStore } from '../store/connectSession';

type Tab = 'now' | 'playlist' | 'request';

const CONNECT_TABS = [
  { id: 'now' as const, label: 'Now Playing', icon: 'music_note' },
  { id: 'playlist' as const, label: 'Playlist', icon: 'queue_music' },
  { id: 'request' as const, label: 'Request', icon: 'add_circle' },
];

export function ConnectShell() {
  const navigate = useNavigate();
  const [tab, setTab] = useState<Tab>('now');
  const connected = useConnectStore((s) => s.connected);
  const sessionId = useConnectStore((s) => s.sessionId);
  const leave = useConnectStore((s) => s.leave);
  const approved = useConnectStore((s) => s.approved);
  const requireApproval = useConnectStore(
    (s) => s.state.settings.requireConnectionApproval,
  );

  useEffect(() => {
    if (!sessionId) navigate('/connect', { replace: true });
  }, [sessionId, navigate]);

  useEffect(() => {
    if (!connected && sessionId) {
      // stay on page with error banner from store
    }
  }, [connected, sessionId]);

  if (!sessionId) return null;

  return (
    <div className="shell">
      <header className="topbar">
        <h1>Connected</h1>
        <span className={`pill ${connected ? 'ok' : 'bad'}`}>
          {connected ? 'Live' : 'Offline'}
        </span>
        <Link to="/" className="icon-btn topbar-action" title="Home" aria-label="Home">
          <span className="material-symbols-outlined">home</span>
        </Link>
        <button
          type="button"
          className="icon-btn topbar-action danger"
          title="Leave session"
          aria-label="Leave session"
          onClick={async () => {
            await leave();
            navigate('/connect');
          }}
        >
          <span className="material-symbols-outlined">logout</span>
        </button>
      </header>

      {!approved && requireApproval && (
        <p className="banner">Waiting for the host to approve your connection…</p>
      )}

      <main className="shell-main">
        {tab === 'now' && <NowPlayingTab />}
        {tab === 'playlist' && <PlaylistTab />}
        {tab === 'request' && <RequestTab />}
      </main>

      <div className="shell-bottom">
        <BottomNav
          label="Connect"
          active={tab}
          onChange={(id) => setTab(id as Tab)}
          items={CONNECT_TABS}
        />
      </div>
    </div>
  );
}

function NowPlayingTab() {
  const state = useConnectStore((s) => s.state);
  const [position, setPosition] = useState(state.positionMs);

  useEffect(() => {
    setPosition(state.positionMs);
  }, [state.positionMs, state.nowPlayingIndex, state.isPlaying]);

  useEffect(() => {
    if (!state.isPlaying) return;
    const timer = setInterval(() => {
      setPosition((p) => Math.min(p + 1000, state.durationMs || p + 1000));
    }, 1000);
    return () => clearInterval(timer);
  }, [state.isPlaying, state.durationMs]);

  const track =
    state.nowPlayingIndex >= 0 ? state.playlist[state.nowPlayingIndex] : null;

  if (!track) {
    return <p className="muted center">Nothing playing yet</p>;
  }

  return (
    <section className="stack center">
      {track.artworkUrl && (
        <img src={track.artworkUrl} alt="" className="hero-art" />
      )}
      <h2>{trackTitle(track)}</h2>
      <p className="muted">{trackArtist(track)}</p>
      <p className="mono">
        {formatMs(position)} / {formatMs(state.durationMs)}
        {state.isPlaying ? '' : ' (paused)'}
      </p>
      <p className="muted small">Audio plays on the host device</p>
    </section>
  );
}

function PlaylistTab() {
  const playlist = useConnectStore((s) => s.state.playlist);
  const nowPlayingIndex = useConnectStore((s) => s.state.nowPlayingIndex);
  const voteScores = useConnectStore((s) => s.state.voteScores);
  const allowVoting = useConnectStore((s) => s.state.settings.allowVoting);
  const voted = useConnectStore((s) => s.votedSongIds);
  const toggleVote = useConnectStore((s) => s.toggleVote);

  return (
    <section className="stack">
      <div className="list">
        {playlist.map((track, index) => {
          const votes = voteScores[track.id] ?? 0;
          const hasVoted = voted.has(track.id);
          return (
            <div
              key={track.id}
              className={`track-row${index === nowPlayingIndex ? ' active' : ''}`}
            >
              {index === nowPlayingIndex ? (
                <span className="now-icon" aria-hidden>
                  <span className="material-symbols-outlined">equalizer</span>
                </span>
              ) : track.artworkUrl ? (
                <img src={track.artworkUrl} alt="" className="art" />
              ) : (
                <div className="art placeholder" />
              )}
              <div className="meta">
                <div className="title">{trackTitle(track)}</div>
                <div className="artist">
                  {trackArtist(track)}
                  {votes > 0 ? ` · ${votes} vote${votes === 1 ? '' : 's'}` : ''}
                </div>
              </div>
              {allowVoting && (
                <button
                  type="button"
                  className={`icon-btn vote-btn${hasVoted ? ' voted' : ''}`}
                  title={hasVoted ? 'Remove vote' : 'Vote'}
                  aria-label={hasVoted ? 'Remove vote' : 'Vote'}
                  aria-pressed={hasVoted}
                  onClick={() => toggleVote(track.id)}
                >
                  <span
                    className={`material-symbols-outlined${hasVoted ? ' filled' : ''}`}
                  >
                    thumb_up
                  </span>
                </button>
              )}
            </div>
          );
        })}
        {playlist.length === 0 && <p className="muted">Playlist is empty</p>}
      </div>
    </section>
  );
}

function RequestTab() {
  const requestTrack = useConnectStore((s) => s.requestTrack);
  const serverUrl = useConnectStore((s) => s.serverUrl);
  const approved = useConnectStore((s) => s.approved);
  const requireApproval = useConnectStore(
    (s) => s.state.settings.requireConnectionApproval,
  );
  const allowSuggestions = useConnectStore((s) => s.state.settings.allowSuggestions);
  const [query, setQuery] = useState('');
  const [results, setResults] = useState<Track[]>([]);
  const [searching, setSearching] = useState(false);
  const [message, setMessage] = useState<string | null>(null);

  const blocked = (requireApproval && !approved) || !allowSuggestions;

  const runSearch = async () => {
    if (!query.trim() || blocked) return;
    setSearching(true);
    setMessage(null);
    try {
      setResults(await searchMusic(query.trim(), serverUrl));
    } catch {
      setResults([]);
      setMessage('Search failed');
    } finally {
      setSearching(false);
    }
  };

  return (
    <section className="stack">
      {blocked && (
        <p className="muted">
          {!allowSuggestions
            ? 'The host has disabled suggestions.'
            : 'Waiting for host approval before you can request songs.'}
        </p>
      )}
      <div className="search-row">
        <input
          value={query}
          disabled={blocked}
          onChange={(e) => setQuery(e.target.value)}
          placeholder="Search YouTube…"
          onKeyDown={(e) => e.key === 'Enter' && void runSearch()}
        />
        <button
          type="button"
          className="btn primary"
          disabled={blocked || searching}
          onClick={() => void runSearch()}
        >
          Search
        </button>
      </div>
      {message && <p className="error">{message}</p>}
      <div className="list">
        {results.map((track) => (
          <TrackRow
            key={track.id}
            track={track}
            actions={
              <button
                type="button"
                className="btn primary small"
                onClick={() => {
                  requestTrack(track);
                  setMessage(`Requested “${trackTitle(track)}”`);
                }}
              >
                Request
              </button>
            }
          />
        ))}
      </div>
    </section>
  );
}

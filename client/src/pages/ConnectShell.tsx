import { useEffect, useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { searchMusic } from '../api/relay';
import { TrackRow, formatMs } from '../components/TrackRow';
import type { Track } from '../protocol/types';
import { useConnectStore } from '../store/connectSession';

type Tab = 'now' | 'playlist' | 'request';

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
      </header>

      {!approved && requireApproval && (
        <p className="banner">Waiting for the host to approve your connection…</p>
      )}

      <nav className="tabs">
        {(
          [
            ['now', 'Now Playing'],
            ['playlist', 'Playlist'],
            ['request', 'Request'],
          ] as const
        ).map(([id, label]) => (
          <button
            key={id}
            type="button"
            className={tab === id ? 'active' : ''}
            onClick={() => setTab(id)}
          >
            {label}
          </button>
        ))}
      </nav>

      <main className="shell-main">
        {tab === 'now' && <NowPlayingTab />}
        {tab === 'playlist' && <PlaylistTab />}
        {tab === 'request' && <RequestTab />}
      </main>

      <footer className="shell-footer">
        <button
          type="button"
          className="btn danger"
          onClick={async () => {
            await leave();
            navigate('/connect');
          }}
        >
          Leave session
        </button>
        <Link to="/" className="muted small">
          Home
        </Link>
      </footer>
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
      <h2>{track.title}</h2>
      <p className="muted">{track.artist}</p>
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
        {playlist.map((track, index) => (
          <TrackRow
            key={track.id}
            track={track}
            active={index === nowPlayingIndex}
            meta={
              allowVoting
                ? `${voteScores[track.id] ?? 0} vote${(voteScores[track.id] ?? 0) === 1 ? '' : 's'}`
                : undefined
            }
            actions={
              allowVoting ? (
                <button
                  type="button"
                  className="btn ghost small"
                  onClick={() => toggleVote(track.id)}
                >
                  {voted.has(track.id) ? 'Unvote' : 'Vote'}
                </button>
              ) : null
            }
          />
        ))}
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
                  setMessage(`Requested “${track.title}”`);
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

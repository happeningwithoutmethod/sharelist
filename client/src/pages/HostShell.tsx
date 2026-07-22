import { useEffect, useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { searchMusic } from '../api/relay';
import { API_ORIGIN } from '../config';
import { QrCode } from '../components/QrCode';
import { TrackRow } from '../components/TrackRow';
import { YoutubePlayer } from '../components/YoutubePlayer';
import type { Track } from '../protocol/types';
import { useHostStore } from '../store/hostSession';

type Tab = 'session' | 'control' | 'lists' | 'request' | 'settings';
type ShareMode = 'app' | 'web' | 'code';

export function HostShell() {
  const navigate = useNavigate();
  const [tab, setTab] = useState<Tab>('session');
  const connected = useHostStore((s) => s.connected);
  const sessionId = useHostStore((s) => s.sessionId);
  const endSession = useHostStore((s) => s.endSession);
  const pending = useHostStore((s) => s.pendingConnections);
  const requests = useHostStore((s) => s.state.pendingRequests);
  const badge = pending.length + requests.length;

  useEffect(() => {
    if (!sessionId) navigate('/host', { replace: true });
  }, [sessionId, navigate]);

  if (!sessionId) return null;

  return (
    <div className="shell">
      <header className="topbar">
        <h1>Host</h1>
        <span className={`pill ${connected ? 'ok' : 'bad'}`}>
          {connected ? 'Live' : 'Offline'}
        </span>
      </header>

      <nav className="tabs">
        {(
          [
            ['session', 'Session'],
            ['control', 'Control'],
            ['lists', 'Lists'],
            ['request', `Request${badge ? ` (${badge})` : ''}`],
            ['settings', 'Settings'],
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
        {tab === 'session' && <SessionTab />}
        {tab === 'control' && <ControlTab />}
        {tab === 'lists' && <ListsTab />}
        {tab === 'request' && <RequestTab />}
        {tab === 'settings' && <SettingsTab />}
      </main>

      {tab !== 'control' && (
        <div className="mini-player">
          <YoutubePlayer compact />
        </div>
      )}

      <footer className="shell-footer">
        <button
          type="button"
          className="btn danger"
          onClick={async () => {
            await endSession();
            navigate('/host');
          }}
        >
          End session
        </button>
        <Link to="/" className="muted small">
          Home
        </Link>
      </footer>
    </div>
  );
}

function SessionTab() {
  const [mode, setMode] = useState<ShareMode>('code');
  const sessionId = useHostStore((s) => s.sessionId)!;
  const joinCode = useHostStore((s) => s.joinCode);
  const serverUrl = useHostStore((s) => s.serverUrl);
  const connectors = useHostStore((s) => s.state.connectors);
  const refreshJoinCode = useHostStore((s) => s.refreshJoinCode);
  const updateSettings = useHostStore((s) => s.updateSettings);
  const allowSuggestions = useHostStore((s) => s.state.settings.allowSuggestions);

  useEffect(() => {
    if (!joinCode) void refreshJoinCode();
  }, [joinCode, refreshJoinCode]);

  const appUrl = `${API_ORIGIN}/join?session=${encodeURIComponent(sessionId)}&server=${encodeURIComponent(serverUrl)}`;
  const webUrl = joinCode
    ? `${API_ORIGIN}/join/${joinCode}`
    : `${API_ORIGIN}/web/?session=${encodeURIComponent(sessionId)}&server=${encodeURIComponent(serverUrl)}`;

  const copy = async (label: string, value: string) => {
    await navigator.clipboard.writeText(value);
    alert(`${label} copied`);
  };

  return (
    <section className="stack">
      <div className="segmented">
        {(['app', 'web', 'code'] as const).map((m) => (
          <button
            key={m}
            type="button"
            className={mode === m ? 'active' : ''}
            onClick={() => setMode(m)}
          >
            {m === 'app' ? 'App' : m === 'web' ? 'Web' : 'Code'}
          </button>
        ))}
      </div>

      {mode === 'code' ? (
        joinCode ? (
          <>
            <p className="muted center">Share this 6-character code.</p>
            <p className="join-code">{joinCode}</p>
            <button type="button" className="btn primary" onClick={() => void copy('Join code', joinCode)}>
              Copy join code
            </button>
          </>
        ) : (
          <div className="center stack">
            <p className="muted">Waiting for a join code from the relay…</p>
            <button type="button" className="btn ghost" onClick={() => void refreshJoinCode()}>
              Retry
            </button>
          </div>
        )
      ) : (
        <>
          <p className="muted center">
            {mode === 'app'
              ? 'Scan to join with the Share List app.'
              : 'Scan to open the join page / web client.'}
          </p>
          <QrCode value={mode === 'app' ? appUrl : webUrl} />
          <button
            type="button"
            className="btn ghost"
            onClick={() => void copy('Join link', mode === 'app' ? appUrl : webUrl)}
          >
            Copy link
          </button>
        </>
      )}

      <p>Connectors: {connectors.length}</p>
      <label className="switch">
        <input
          type="checkbox"
          checked={allowSuggestions}
          onChange={(e) => updateSettings({ allowSuggestions: e.target.checked })}
        />
        Allow suggestions
      </label>
      <p className="muted small">Session ID</p>
      <code className="mono">{sessionId}</code>
      {joinCode && (
        <>
          <p className="muted small">Join code</p>
          <code className="mono">{joinCode}</code>
        </>
      )}
    </section>
  );
}

function ControlTab() {
  const state = useHostStore((s) => s.state);
  const updatePlayback = useHostStore((s) => s.updatePlayback);
  const playIndex = useHostStore((s) => s.playIndex);
  const track =
    state.nowPlayingIndex >= 0 ? state.playlist[state.nowPlayingIndex] : null;

  return (
    <section className="stack">
      <YoutubePlayer />
      {track ? (
        <div>
          <h2>{track.title}</h2>
          <p className="muted">{track.artist}</p>
        </div>
      ) : (
        <p className="muted">Nothing playing</p>
      )}
      <div className="transport">
        <button
          type="button"
          className="btn ghost"
          onClick={() => playIndex(Math.max(0, state.nowPlayingIndex - 1))}
        >
          Prev
        </button>
        <button
          type="button"
          className="btn primary"
          onClick={() => updatePlayback({ isPlaying: !state.isPlaying })}
        >
          {state.isPlaying ? 'Pause' : 'Play'}
        </button>
        <button
          type="button"
          className="btn ghost"
          onClick={() =>
            playIndex(
              Math.min(state.playlist.length - 1, state.nowPlayingIndex + 1),
            )
          }
        >
          Next
        </button>
      </div>
    </section>
  );
}

function ListsTab() {
  const playlist = useHostStore((s) => s.state.playlist);
  const nowPlayingIndex = useHostStore((s) => s.state.nowPlayingIndex);
  const addTrack = useHostStore((s) => s.addTrack);
  const removeTrack = useHostStore((s) => s.removeTrack);
  const playIndex = useHostStore((s) => s.playIndex);
  const serverUrl = useHostStore((s) => s.serverUrl);
  const [query, setQuery] = useState('');
  const [results, setResults] = useState<Track[]>([]);
  const [searching, setSearching] = useState(false);

  const runSearch = async () => {
    if (!query.trim()) return;
    setSearching(true);
    try {
      setResults(await searchMusic(query.trim(), serverUrl));
    } catch {
      setResults([]);
    } finally {
      setSearching(false);
    }
  };

  return (
    <section className="stack">
      <div className="search-row">
        <input
          value={query}
          onChange={(e) => setQuery(e.target.value)}
          placeholder="Search YouTube…"
          onKeyDown={(e) => e.key === 'Enter' && void runSearch()}
        />
        <button type="button" className="btn primary" disabled={searching} onClick={() => void runSearch()}>
          Search
        </button>
      </div>
      {results.length > 0 && (
        <div className="list">
          {results.map((track) => (
            <TrackRow
              key={track.id}
              track={track}
              actions={
                <button type="button" className="btn ghost small" onClick={() => addTrack(track)}>
                  Add
                </button>
              }
            />
          ))}
        </div>
      )}
      <h3>Playlist ({playlist.length})</h3>
      <div className="list">
        {playlist.map((track, index) => (
          <TrackRow
            key={track.id}
            track={track}
            active={index === nowPlayingIndex}
            actions={
              <>
                <button type="button" className="btn ghost small" onClick={() => playIndex(index)}>
                  Play
                </button>
                <button type="button" className="btn ghost small" onClick={() => removeTrack(track.id)}>
                  Remove
                </button>
              </>
            }
          />
        ))}
        {playlist.length === 0 && <p className="muted">Playlist is empty</p>}
      </div>
    </section>
  );
}

function RequestTab() {
  const pending = useHostStore((s) => s.pendingConnections);
  const requests = useHostStore((s) => s.state.pendingRequests);
  const approveConnector = useHostStore((s) => s.approveConnector);
  const rejectConnector = useHostStore((s) => s.rejectConnector);
  const approveRequest = useHostStore((s) => s.approveRequest);
  const rejectRequest = useHostStore((s) => s.rejectRequest);

  return (
    <section className="stack">
      <h3>Connections</h3>
      {pending.length === 0 && <p className="muted">No pending connections</p>}
      {pending.map((c) => (
        <div key={c.deviceId} className="row-card">
          <div>
            <strong>{c.displayName}</strong>
            <div className="muted small">{c.deviceId.slice(0, 8)}…</div>
          </div>
          <div className="actions">
            <button type="button" className="btn primary small" onClick={() => approveConnector(c.deviceId)}>
              Approve
            </button>
            <button type="button" className="btn ghost small" onClick={() => rejectConnector(c.deviceId)}>
              Reject
            </button>
          </div>
        </div>
      ))}

      <h3>Song requests</h3>
      {requests.length === 0 && <p className="muted">No pending requests</p>}
      {requests.map((r) => (
        <TrackRow
          key={r.id}
          track={r.track}
          meta={`from ${r.requestedBy}`}
          actions={
            <>
              <button type="button" className="btn primary small" onClick={() => approveRequest(r.id, 'bottom')}>
                Add
              </button>
              <button type="button" className="btn ghost small" onClick={() => approveRequest(r.id, 'top')}>
                Next
              </button>
              <button type="button" className="btn ghost small" onClick={() => rejectRequest(r.id)}>
                Reject
              </button>
            </>
          }
        />
      ))}
    </section>
  );
}

function SettingsTab() {
  const settings = useHostStore((s) => s.state.settings);
  const updateSettings = useHostStore((s) => s.updateSettings);
  const rows: Array<{ key: keyof typeof settings; label: string }> = [
    { key: 'allowSuggestions', label: 'Allow suggestions' },
    { key: 'allowVoting', label: 'Allow voting' },
    { key: 'autoReorderByVotes', label: 'Auto-reorder by votes' },
    { key: 'autoPlaylistAdvance', label: 'Auto-advance playlist' },
    { key: 'autoApproveRequests', label: 'Auto-approve song requests' },
    { key: 'requireConnectionApproval', label: 'Require connection approval' },
  ];

  return (
    <section className="stack">
      {rows.map(({ key, label }) => (
        <label key={key} className="switch">
          <input
            type="checkbox"
            checked={settings[key]}
            onChange={(e) => updateSettings({ [key]: e.target.checked })}
          />
          {label}
        </label>
      ))}
    </section>
  );
}

import { useEffect, useRef, useState } from 'react';
import { Link, useNavigate } from 'react-router-dom';
import { searchMusic } from '../api/relay';
import { API_ORIGIN } from '../config';
import { BottomNav } from '../components/BottomNav';
import { QrCode } from '../components/QrCode';
import { TrackRow } from '../components/TrackRow';
import { YoutubePlayer } from '../components/YoutubePlayer';
import {
  downloadLst,
  parseLst,
  playlistToShareText,
  sanitizeLstFilename,
  serializeLst,
} from '../lib/playlistFile';
import { trackArtist, trackTitle } from '../lib/trackText';
import type { Track } from '../protocol/types';
import { useHostStore } from '../store/hostSession';

type Tab = 'session' | 'control' | 'lists' | 'request' | 'settings';
type ShareMode = 'app' | 'web' | 'code';

const HOST_TABS = [
  { id: 'session' as const, label: 'Session', icon: 'qr_code_2' },
  { id: 'control' as const, label: 'Control', icon: 'play_circle' },
  { id: 'lists' as const, label: 'Lists', icon: 'queue_music' },
  { id: 'request' as const, label: 'Request', icon: 'inbox' },
  { id: 'settings' as const, label: 'Settings', icon: 'settings' },
];

export function HostShell() {
  const navigate = useNavigate();
  const [tab, setTab] = useState<Tab>('session');
  const connected = useHostStore((s) => s.connected);
  const sessionId = useHostStore((s) => s.sessionId);
  const endSession = useHostStore((s) => s.endSession);
  const pending = useHostStore((s) => s.pendingConnections);
  const requests = useHostStore((s) => s.state.pendingRequests);
  const nowPlayingIndex = useHostStore((s) => s.state.nowPlayingIndex);
  const playlist = useHostStore((s) => s.state.playlist);
  const syncNowPlayingWithPlaylist = useHostStore(
    (s) => s.syncNowPlayingWithPlaylist,
  );
  const badge = pending.length + requests.length;
  const hasActiveTrack =
    nowPlayingIndex >= 0 && nowPlayingIndex < playlist.length;
  const showPlayer = tab === 'control' || hasActiveTrack;

  useEffect(() => {
    if (!sessionId) navigate('/host', { replace: true });
  }, [sessionId, navigate]);

  useEffect(() => {
    if (playlist.length > 0 && nowPlayingIndex < 0) {
      syncNowPlayingWithPlaylist();
    }
  }, [playlist.length, nowPlayingIndex, syncNowPlayingWithPlaylist]);

  if (!sessionId) return null;

  return (
    <div className="shell">
      <header className="topbar">
        <h1>Host</h1>
        <span className={`pill ${connected ? 'ok' : 'bad'}`}>
          {connected ? 'Live' : 'Offline'}
        </span>
        <Link to="/" className="icon-btn topbar-action" title="Home" aria-label="Home">
          <span className="material-symbols-outlined">home</span>
        </Link>
        <button
          type="button"
          className="icon-btn topbar-action danger"
          title="End session"
          aria-label="End session"
          onClick={async () => {
            await endSession();
            navigate('/host');
          }}
        >
          <span className="material-symbols-outlined">logout</span>
        </button>
      </header>

      {showPlayer && (
        <div className={`player-slot ${tab === 'control' ? 'expanded' : 'compact'}`}>
          <YoutubePlayer compact={tab !== 'control'} />
        </div>
      )}

      <main className="shell-main">
        {tab === 'session' && <SessionTab />}
        {tab === 'control' && <ControlTab />}
        {tab === 'lists' && <ListsTab />}
        {tab === 'request' && <RequestTab />}
        {tab === 'settings' && <SettingsTab />}
      </main>

      <div className="shell-bottom">
        <BottomNav
          label="Host"
          active={tab}
          onChange={(id) => setTab(id as Tab)}
          items={HOST_TABS.map((item) =>
            item.id === 'request' ? { ...item, badge } : item,
          )}
        />
      </div>
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
        <span>Allow suggestions</span>
        <input
          type="checkbox"
          checked={allowSuggestions}
          onChange={(e) => updateSettings({ allowSuggestions: e.target.checked })}
        />
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
      {track ? (
        <div>
          <h2>{trackTitle(track)}</h2>
          <p className="muted">{trackArtist(track)}</p>
        </div>
      ) : (
        <p className="muted">Nothing playing</p>
      )}
      <div className="transport" role="group" aria-label="Playback">
        <button
          type="button"
          className="transport-btn"
          title="Previous"
          aria-label="Previous"
          disabled={state.playlist.length === 0}
          onClick={() => playIndex(Math.max(0, state.nowPlayingIndex - 1))}
        >
          <span className="material-symbols-outlined">skip_previous</span>
        </button>
        <button
          type="button"
          className="transport-btn transport-btn-play"
          title={state.isPlaying ? 'Pause' : 'Play'}
          aria-label={state.isPlaying ? 'Pause' : 'Play'}
          disabled={!track}
          onClick={() => updatePlayback({ isPlaying: !state.isPlaying })}
        >
          <span className="material-symbols-outlined filled">
            {state.isPlaying ? 'pause_circle' : 'play_circle'}
          </span>
        </button>
        <button
          type="button"
          className="transport-btn"
          title="Next"
          aria-label="Next"
          disabled={state.playlist.length === 0}
          onClick={() =>
            playIndex(
              Math.min(state.playlist.length - 1, state.nowPlayingIndex + 1),
            )
          }
        >
          <span className="material-symbols-outlined">skip_next</span>
        </button>
      </div>
    </section>
  );
}

function ListsTab() {
  const playlist = useHostStore((s) => s.state.playlist);
  const sessionName = useHostStore((s) => s.state.sessionName);
  const nowPlayingIndex = useHostStore((s) => s.state.nowPlayingIndex);
  const voteScores = useHostStore((s) => s.state.voteScores);
  const allowVoting = useHostStore((s) => s.state.settings.allowVoting);
  const addTrack = useHostStore((s) => s.addTrack);
  const removeTrack = useHostStore((s) => s.removeTrack);
  const replacePlaylist = useHostStore((s) => s.replacePlaylist);
  const moveTrack = useHostStore((s) => s.moveTrack);
  const moveTrackToTop = useHostStore((s) => s.moveTrackToTop);
  const moveTrackToBottom = useHostStore((s) => s.moveTrackToBottom);
  const playIndex = useHostStore((s) => s.playIndex);
  const serverUrl = useHostStore((s) => s.serverUrl);
  const [query, setQuery] = useState('');
  const [results, setResults] = useState<Track[]>([]);
  const [searching, setSearching] = useState(false);
  const [status, setStatus] = useState<string | null>(null);
  const [dragIndex, setDragIndex] = useState<number | null>(null);
  const fileRef = useRef<HTMLInputElement>(null);

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

  const sharePlaylist = async () => {
    if (playlist.length === 0) return;
    const text = playlistToShareText(sessionName, playlist);
    try {
      await navigator.clipboard.writeText(text);
      setStatus('Playlist copied to clipboard');
    } catch {
      setStatus('Could not copy to clipboard');
    }
  };

  const savePlaylist = () => {
    if (playlist.length === 0) return;
    const name = window.prompt('Playlist name', sessionName || 'Playlist');
    if (name == null) return;
    const trimmed = name.trim();
    if (!trimmed) return;
    downloadLst(
      sanitizeLstFilename(trimmed),
      serializeLst({ name: trimmed, tracks: playlist }),
    );
    setStatus(`Saved “${trimmed}.lst”`);
  };

  const loadFromFile = async (file: File) => {
    try {
      const parsed = parseLst(await file.text());
      if (playlist.length > 0) {
        const ok = window.confirm(
          `Load “${parsed.name}” and replace the current playlist (${playlist.length} songs)?`,
        );
        if (!ok) return;
      }
      replacePlaylist(parsed.tracks);
      setStatus(`Loaded “${parsed.name}” (${parsed.tracks.length} songs)`);
    } catch (error) {
      setStatus(error instanceof Error ? error.message : 'Failed to load .lst');
    }
  };

  return (
    <section className="stack">
      <div className="list-toolbar">
        <button
          type="button"
          className="icon-btn"
          title="Load playlist"
          aria-label="Load playlist"
          onClick={() => fileRef.current?.click()}
        >
          <span className="material-symbols-outlined">file_open</span>
        </button>
        <button
          type="button"
          className="icon-btn"
          title="Share playlist"
          aria-label="Share playlist"
          disabled={playlist.length === 0}
          onClick={() => void sharePlaylist()}
        >
          <span className="material-symbols-outlined">share</span>
        </button>
        <span className="list-toolbar-spacer" />
        <button
          type="button"
          className="icon-btn"
          title="Save playlist"
          aria-label="Save playlist"
          disabled={playlist.length === 0}
          onClick={savePlaylist}
        >
          <span className="material-symbols-outlined">file_download</span>
        </button>
        <input
          ref={fileRef}
          type="file"
          accept=".lst,application/json"
          hidden
          onChange={(e) => {
            const file = e.target.files?.[0];
            e.target.value = '';
            if (file) void loadFromFile(file);
          }}
        />
      </div>
      {status && <p className="muted small">{status}</p>}

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
                <button
                  type="button"
                  className="btn ghost small"
                  onClick={() => {
                    addTrack(track);
                    setResults([]);
                    setQuery('');
                  }}
                >
                  Add
                </button>
              }
            />
          ))}
        </div>
      )}
      <h3>Playlist ({playlist.length})</h3>
      <div className="list">
        {playlist.map((track, index) => {
          const votes = voteScores[track.id] ?? 0;
          return (
            <div
              key={track.id}
              className={`track-row${index === nowPlayingIndex ? ' active' : ''}${dragIndex === index ? ' dragging' : ''}`}
              draggable
              onDragStart={(e) => {
                setDragIndex(index);
                e.dataTransfer.effectAllowed = 'move';
                e.dataTransfer.setData('text/plain', String(index));
              }}
              onDragEnd={() => setDragIndex(null)}
              onDragOver={(e) => {
                e.preventDefault();
                e.dataTransfer.dropEffect = 'move';
              }}
              onDrop={(e) => {
                e.preventDefault();
                const from = Number(e.dataTransfer.getData('text/plain'));
                setDragIndex(null);
                if (Number.isFinite(from) && from !== index) moveTrack(from, index);
              }}
            >
              <span className="drag-handle" title="Drag to reorder" aria-hidden>
                <span className="material-symbols-outlined">drag_handle</span>
              </span>
              {track.artworkUrl ? (
                <img src={track.artworkUrl} alt="" className="art" />
              ) : (
                <div className="art placeholder" />
              )}
              <button type="button" className="linkish meta" onClick={() => playIndex(index)}>
                <div className="title">{trackTitle(track)}</div>
                <div className="artist">
                  {trackArtist(track)}
                  {allowVoting && votes > 0
                    ? ` · ${votes} vote${votes === 1 ? '' : 's'}`
                    : ''}
                </div>
              </button>
              <details className="track-menu">
                <summary className="icon-btn" aria-label="Track actions">
                  <span className="material-symbols-outlined">more_vert</span>
                </summary>
                <div className="track-menu-panel" role="menu">
                  <button type="button" role="menuitem" onClick={() => playIndex(index)}>
                    Play now
                  </button>
                  <button
                    type="button"
                    role="menuitem"
                    disabled={index === 0}
                    onClick={() => moveTrackToTop(index)}
                  >
                    Move to top
                  </button>
                  <button
                    type="button"
                    role="menuitem"
                    disabled={index >= playlist.length - 1}
                    onClick={() => moveTrackToBottom(index)}
                  >
                    Move to bottom
                  </button>
                  <button
                    type="button"
                    role="menuitem"
                    onClick={() => removeTrack(track.id)}
                  >
                    Remove
                  </button>
                </div>
              </details>
            </div>
          );
        })}
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
  const restoreDefaultSettings = useHostStore((s) => s.restoreDefaultSettings);
  const [status, setStatus] = useState<string | null>(null);

  const rows: Array<{
    key: keyof typeof settings;
    label: string;
    subtitle?: string;
    disabled?: boolean;
  }> = [
    {
      key: 'allowVoting',
      label: 'Allow playlist songs to be voted for',
    },
    {
      key: 'autoReorderByVotes',
      label: 'Auto move songs based on votes',
      subtitle: 'Queue below now-playing reorders by vote score',
      disabled: !settings.allowVoting,
    },
    {
      key: 'autoPlaylistAdvance',
      label: 'Auto playlist advance',
      subtitle: 'Play the next song when the current one finishes',
    },
    {
      key: 'autoApproveRequests',
      label: 'Auto approve requests',
      subtitle: 'Add requested songs to the bottom of the playlist automatically',
    },
    {
      key: 'requireConnectionApproval',
      label: 'New connections need approval',
      subtitle:
        'Approve connectors on the Request tab before they can request songs',
    },
  ];

  return (
    <section className="stack">
      {rows.map(({ key, label, subtitle, disabled }) => (
        <label
          key={key}
          className={`switch${disabled ? ' disabled' : ''}`}
        >
          <span className="switch-copy">
            <span className="switch-title">{label}</span>
            {subtitle && <span className="switch-subtitle">{subtitle}</span>}
          </span>
          <input
            type="checkbox"
            checked={settings[key]}
            disabled={disabled}
            onChange={(e) => updateSettings({ [key]: e.target.checked })}
          />
        </label>
      ))}
      <hr className="settings-divider" />
      <button
        type="button"
        className="btn ghost"
        onClick={() => {
          restoreDefaultSettings();
          setStatus('Host settings restored to defaults');
        }}
      >
        <span className="material-symbols-outlined">restart_alt</span>
        Restore defaults
      </button>
      {status && <p className="muted small">{status}</p>}
      <p className="muted small">
        Settings are remembered for the next session you start.
      </p>
    </section>
  );
}

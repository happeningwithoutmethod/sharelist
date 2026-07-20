import type { IncomingMessage, ServerResponse } from 'node:http';
import type { PlayLog } from './play-log.js';
import {
  clearRelayInfoPasskeyCookie,
  isRelayInfoAuthorized,
  readPasskeyFromPost,
  sendUnauthorized,
  setRelayInfoPasskeyCookie,
  verifyRelayPasskey,
} from './relay-auth.js';
import type { SessionStore } from './session/store.js';

function escapeHtml(value: string): string {
  return value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');
}

function formatMs(ms: number): string {
  if (!Number.isFinite(ms) || ms < 0) return '0:00';
  const totalSec = Math.floor(ms / 1000);
  const m = Math.floor(totalSec / 60);
  const s = totalSec % 60;
  return `${m}:${s.toString().padStart(2, '0')}`;
}

/** Format an ISO UTC timestamp for display (keep UTC label). */
function formatUtc(iso: string): string {
  try {
    const d = new Date(iso);
    if (Number.isNaN(d.getTime())) return iso;
    return d.toISOString().replace('T', ' ').replace(/\.\d{3}Z$/, ' UTC');
  } catch {
    return iso;
  }
}

export function buildDashboardPayload(store: SessionStore, playLog?: PlayLog) {
  const sessions = store.listSessions().map((session) => {
    const state = session.stateSnapshot;
    const index = state.nowPlayingIndex;
    const track =
      index >= 0 && index < state.playlist.length ? state.playlist[index] : null;

    return {
      sessionId: session.id,
      sessionName: state.sessionName,
      status: session.status,
      hostConnected: session.hostSocket != null,
      connectorCount: session.connectors.size,
      connectors: [...session.connectors.values()].map((c) => ({
        deviceId: c.deviceId,
        displayName: c.displayName,
      })),
      playlistLength: state.playlist.length,
      isPlaying: state.isPlaying,
      positionMs: state.positionMs,
      durationMs: state.durationMs,
      nowPlaying: track
        ? {
            id: track.id,
            title: track.title,
            artist: track.artist,
            artworkUrl: track.artworkUrl,
          }
        : null,
    };
  });

  const plays = playLog?.toDashboardPayload() ?? {
    generatedAt: new Date().toISOString(),
    totalPlays: 0,
    uniqueSongs: 0,
    popularSongs: [],
    recentPlays: [],
  };

  return {
    generatedAt: new Date().toISOString(),
    sessionCount: sessions.length,
    sessions,
    plays,
  };
}

function renderDashboardHtml(store: SessionStore, playLog: PlayLog): string {
  const payload = buildDashboardPayload(store, playLog);
  const rows =
    payload.sessions.length === 0
      ? `<tr><td colspan="5" class="empty">No active sessions</td></tr>`
      : payload.sessions
          .map((session) => {
            const playing = session.nowPlaying
              ? `${escapeHtml(session.nowPlaying.title)}<br><span class="muted">${escapeHtml(session.nowPlaying.artist)}</span>`
              : '<span class="muted">Nothing playing</span>';
            const progress =
              session.nowPlaying != null
                ? `${formatMs(session.positionMs)} / ${formatMs(session.durationMs)}${session.isPlaying ? '' : ' (paused)'}`
                : '—';
            const host = session.hostConnected ? 'online' : 'offline';
            return `<tr>
  <td>
    <div class="name">${escapeHtml(session.sessionName)}</div>
    <div class="muted mono">${escapeHtml(session.sessionId.slice(0, 8))}…</div>
  </td>
  <td><span class="badge ${session.status}">${escapeHtml(session.status)}</span></td>
  <td><span class="badge host-${host}">host ${host}</span></td>
  <td class="num">${session.connectorCount}</td>
  <td>
    <div>${playing}</div>
    <div class="muted">${escapeHtml(progress)}</div>
  </td>
</tr>`;
          })
          .join('\n');

  const popularRows =
    payload.plays.popularSongs.length === 0
      ? `<tr><td colspan="5" class="empty">No plays recorded yet</td></tr>`
      : payload.plays.popularSongs
          .map((song, i) => {
            return `<tr>
  <td class="num">${i + 1}</td>
  <td>
    <div class="name">${escapeHtml(song.title)}</div>
    <div class="muted">${escapeHtml(song.artist)}</div>
  </td>
  <td class="num">${song.playCount}</td>
  <td class="num">${song.likes}</td>
  <td class="muted mono">${escapeHtml(formatUtc(song.lastPlayedAt))}</td>
</tr>`;
          })
          .join('\n');

  const recentRows =
    payload.plays.recentPlays.length === 0
      ? `<tr><td colspan="4" class="empty">No play events yet</td></tr>`
      : payload.plays.recentPlays
          .map((play) => {
            return `<tr>
  <td class="muted mono">${escapeHtml(formatUtc(play.playedAt))}</td>
  <td>
    <div class="name">${escapeHtml(play.track.title)}</div>
    <div class="muted">${escapeHtml(play.track.artist)}</div>
  </td>
  <td>
    <div>${escapeHtml(play.sessionName)}</div>
    <div class="muted mono">${escapeHtml(play.sessionId.slice(0, 8))}…</div>
  </td>
  <td class="num">${play.likes}</td>
</tr>`;
          })
          .join('\n');

  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Share List — Server Dashboard</title>
  <style>
    :root {
      color-scheme: dark;
      --bg: #0f1419;
      --panel: #1a222c;
      --text: #e7eef7;
      --muted: #8b9bb0;
      --line: #2a3542;
      --accent: #5b9fd4;
      --ok: #3d9a6a;
      --warn: #c9a227;
      --bad: #c45c5c;
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      font-family: "Segoe UI", system-ui, sans-serif;
      background: radial-gradient(1200px 600px at 10% -10%, #1b2a3a, var(--bg));
      color: var(--text);
      min-height: 100vh;
    }
    main { max-width: 1100px; margin: 0 auto; padding: 32px 20px 48px; }
    h1 { margin: 0 0 8px; font-size: 1.75rem; letter-spacing: -0.02em; }
    h2 { margin: 32px 0 12px; font-size: 1.15rem; letter-spacing: -0.01em; }
    .sub { color: var(--muted); margin-bottom: 24px; }
    .stats {
      display: flex; gap: 12px; flex-wrap: wrap; margin-bottom: 20px;
    }
    .stat {
      background: var(--panel);
      border: 1px solid var(--line);
      border-radius: 12px;
      padding: 14px 18px;
      min-width: 140px;
    }
    .stat .label { color: var(--muted); font-size: 0.8rem; }
    .stat .value { font-size: 1.6rem; font-weight: 650; margin-top: 4px; }
    table {
      width: 100%;
      border-collapse: collapse;
      background: var(--panel);
      border: 1px solid var(--line);
      border-radius: 12px;
      overflow: hidden;
    }
    th, td {
      text-align: left;
      padding: 14px 16px;
      border-bottom: 1px solid var(--line);
      vertical-align: top;
    }
    th {
      font-size: 0.75rem;
      text-transform: uppercase;
      letter-spacing: 0.04em;
      color: var(--muted);
      background: #151c24;
    }
    tr:last-child td { border-bottom: none; }
    .name { font-weight: 600; }
    .muted { color: var(--muted); font-size: 0.85rem; }
    .mono { font-family: ui-monospace, SFMono-Regular, Menlo, Consolas, monospace; }
    .num { font-variant-numeric: tabular-nums; font-size: 1.2rem; font-weight: 650; }
    .empty { text-align: center; color: var(--muted); padding: 36px 16px; }
    .badge {
      display: inline-block;
      padding: 2px 8px;
      border-radius: 999px;
      font-size: 0.75rem;
      border: 1px solid var(--line);
      background: #121820;
    }
    .badge.active { color: #9ee0b8; border-color: #2f6b4c; }
    .badge.orphaned { color: #f0d889; border-color: #7a6520; }
    .badge.ended { color: #f0a8a8; border-color: #7a3030; }
    .badge.host-online { color: #9ee0b8; }
    .badge.host-offline { color: #f0d889; }
    a.json { color: var(--accent); }
    .section-note { color: var(--muted); font-size: 0.85rem; margin: -4px 0 12px; }
  </style>
</head>
<body>
  <main>
    <h1>Share List relay</h1>
    <p class="sub">
      Live sessions · song play log (UTC) · live updates every 5s ·
      <a class="json" href="/relay/info/api/dashboard">dashboard JSON</a> ·
      <a class="json" href="/relay/info/api/plays">plays JSON</a> ·
      <a class="json" href="/">public landing</a>
    </p>
    <div class="stats">
      <div class="stat">
        <div class="label">Active sessions</div>
        <div class="value" id="stat-sessions">${payload.sessionCount}</div>
      </div>
      <div class="stat">
        <div class="label">Total connectors</div>
        <div class="value" id="stat-connectors">${payload.sessions.reduce((n, s) => n + s.connectorCount, 0)}</div>
      </div>
      <div class="stat">
        <div class="label">Total plays</div>
        <div class="value" id="stat-plays">${payload.plays.totalPlays}</div>
      </div>
      <div class="stat">
        <div class="label">Unique songs</div>
        <div class="value" id="stat-unique">${payload.plays.uniqueSongs}</div>
      </div>
      <div class="stat">
        <div class="label">Updated</div>
        <div class="value" id="stat-updated" style="font-size:1rem;margin-top:10px">${escapeHtml(new Date(payload.generatedAt).toLocaleTimeString())}</div>
      </div>
    </div>

    <h2>Live sessions</h2>
    <table>
      <thead>
        <tr>
          <th>Session</th>
          <th>Status</th>
          <th>Host</th>
          <th>Connectors</th>
          <th>Now playing</th>
        </tr>
      </thead>
      <tbody id="sessions-body">
        ${rows}
      </tbody>
    </table>

    <h2>Popular songs</h2>
    <p class="section-note">Ordered by play count, then likes. Timestamps are UTC.</p>
    <table>
      <thead>
        <tr>
          <th>#</th>
          <th>Song</th>
          <th>Plays</th>
          <th>Likes</th>
          <th>Last played (UTC)</th>
        </tr>
      </thead>
      <tbody id="popular-body">
        ${popularRows}
      </tbody>
    </table>

    <h2>Play log</h2>
    <p class="section-note">Recent plays across sessions · newest first · UTC</p>
    <table>
      <thead>
        <tr>
          <th>Played at (UTC)</th>
          <th>Song</th>
          <th>Session</th>
          <th>Likes</th>
        </tr>
      </thead>
      <tbody id="recent-body">
        ${recentRows}
      </tbody>
    </table>
  </main>
  <script>
(() => {
  function esc(value) {
    return String(value ?? '')
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
  }

  function formatMs(ms) {
    if (!Number.isFinite(ms) || ms < 0) return '0:00';
    const totalSec = Math.floor(ms / 1000);
    const m = Math.floor(totalSec / 60);
    const s = totalSec % 60;
    return m + ':' + String(s).padStart(2, '0');
  }

  function formatUtc(iso) {
    try {
      const d = new Date(iso);
      if (Number.isNaN(d.getTime())) return iso;
      return d.toISOString().slice(0, 19).replace('T', ' ') + ' UTC';
    } catch {
      return iso;
    }
  }

  function sessionsHtml(sessions) {
    if (!sessions.length) {
      return '<tr><td colspan="5" class="empty">No active sessions</td></tr>';
    }
    return sessions.map((session) => {
      const playing = session.nowPlaying
        ? esc(session.nowPlaying.title) + '<br><span class="muted">' + esc(session.nowPlaying.artist) + '</span>'
        : '<span class="muted">Nothing playing</span>';
      const progress = session.nowPlaying != null
        ? formatMs(session.positionMs) + ' / ' + formatMs(session.durationMs) + (session.isPlaying ? '' : ' (paused)')
        : '—';
      const host = session.hostConnected ? 'online' : 'offline';
      return '<tr><td><div class="name">' + esc(session.sessionName) + '</div>'
        + '<div class="muted mono">' + esc(session.sessionId.slice(0, 8)) + '…</div></td>'
        + '<td><span class="badge ' + esc(session.status) + '">' + esc(session.status) + '</span></td>'
        + '<td><span class="badge host-' + host + '">host ' + host + '</span></td>'
        + '<td class="num">' + session.connectorCount + '</td>'
        + '<td><div>' + playing + '</div><div class="muted">' + esc(progress) + '</div></td></tr>';
    }).join('');
  }

  function popularHtml(songs) {
    if (!songs.length) {
      return '<tr><td colspan="5" class="empty">No plays recorded yet</td></tr>';
    }
    return songs.map((song, i) =>
      '<tr><td class="num">' + (i + 1) + '</td><td><div class="name">' + esc(song.title)
      + '</div><div class="muted">' + esc(song.artist) + '</div></td>'
      + '<td class="num">' + song.playCount + '</td><td class="num">' + song.likes + '</td>'
      + '<td class="muted mono">' + esc(formatUtc(song.lastPlayedAt)) + '</td></tr>'
    ).join('');
  }

  function recentHtml(plays) {
    if (!plays.length) {
      return '<tr><td colspan="4" class="empty">No play events yet</td></tr>';
    }
    return plays.map((play) =>
      '<tr><td class="muted mono">' + esc(formatUtc(play.playedAt)) + '</td>'
      + '<td><div class="name">' + esc(play.track.title) + '</div><div class="muted">'
      + esc(play.track.artist) + '</div></td>'
      + '<td><div>' + esc(play.sessionName) + '</div><div class="muted mono">'
      + esc(play.sessionId.slice(0, 8)) + '…</div></td>'
      + '<td class="num">' + play.likes + '</td></tr>'
    ).join('');
  }

  function apply(payload) {
    const connectors = payload.sessions.reduce((n, s) => n + s.connectorCount, 0);
    document.getElementById('stat-sessions').textContent = String(payload.sessionCount);
    document.getElementById('stat-connectors').textContent = String(connectors);
    document.getElementById('stat-plays').textContent = String(payload.plays.totalPlays);
    document.getElementById('stat-unique').textContent = String(payload.plays.uniqueSongs);
    document.getElementById('stat-updated').textContent = new Date(payload.generatedAt).toLocaleTimeString();
    document.getElementById('sessions-body').innerHTML = sessionsHtml(payload.sessions);
    document.getElementById('popular-body').innerHTML = popularHtml(payload.plays.popularSongs || []);
    document.getElementById('recent-body').innerHTML = recentHtml(payload.plays.recentPlays || []);
  }

  async function refresh() {
    try {
      const res = await fetch('/relay/info/api/dashboard', { cache: 'no-store', credentials: 'same-origin' });
      if (!res.ok) return;
      apply(await res.json());
    } catch (_) { /* keep last good snapshot */ }
  }

  setInterval(refresh, 5000);
  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'visible') refresh();
  });
})();
  </script>
</body>
</html>`;
}

function requireRelayInfoAuth(
  req: IncomingMessage,
  res: ServerResponse,
  url: URL,
  htmlLogin: boolean,
): boolean {
  if (isRelayInfoAuthorized(req, url)) return true;
  sendUnauthorized(res, { htmlLogin });
  return false;
}

export function handleDashboard(
  req: IncomingMessage,
  res: ServerResponse,
  url: URL,
  store: SessionStore,
  playLog: PlayLog,
): boolean {
  if (url.pathname === '/relay/info/login' && req.method === 'POST') {
    void (async () => {
      const passkey = await readPasskeyFromPost(req);
      if (!verifyRelayPasskey(passkey)) {
        clearRelayInfoPasskeyCookie(res);
        sendUnauthorized(res, { htmlLogin: true });
        return;
      }
      setRelayInfoPasskeyCookie(res, passkey!);
      res.writeHead(303, { Location: '/relay/info' });
      res.end();
    })();
    return true;
  }

  if (url.pathname === '/relay/info/logout' && (req.method === 'GET' || req.method === 'POST')) {
    clearRelayInfoPasskeyCookie(res);
    res.writeHead(303, { Location: '/relay/info' });
    res.end();
    return true;
  }

  const isRelayInfoPage =
    (url.pathname === '/relay/info' || url.pathname === '/dashboard') &&
    req.method === 'GET';
  const isRelayDashboardApi =
    url.pathname === '/relay/info/api/dashboard' && req.method === 'GET';
  const isRelayPlaysApi = url.pathname === '/relay/info/api/plays' && req.method === 'GET';
  /** Legacy admin API paths — keep working but require the same passkey. */
  const isLegacyDashboardApi = url.pathname === '/api/dashboard' && req.method === 'GET';
  const isLegacyPlaysApi = url.pathname === '/api/plays' && req.method === 'GET';

  if (isRelayInfoPage) {
    if (!requireRelayInfoAuth(req, res, url, true)) return true;
    res.writeHead(200, {
      'Content-Type': 'text/html; charset=utf-8',
      'Cache-Control': 'no-store',
    });
    res.end(renderDashboardHtml(store, playLog));
    return true;
  }

  if (
    isRelayDashboardApi ||
    isRelayPlaysApi ||
    isLegacyDashboardApi ||
    isLegacyPlaysApi
  ) {
    if (!requireRelayInfoAuth(req, res, url, false)) return true;
    const body =
      isRelayPlaysApi || isLegacyPlaysApi
        ? playLog.toDashboardPayload()
        : buildDashboardPayload(store, playLog);
    res.writeHead(200, {
      'Content-Type': 'application/json',
      'Cache-Control': 'no-store',
    });
    res.end(JSON.stringify(body, null, 2));
    return true;
  }

  return false;
}

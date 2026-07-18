import type { IncomingMessage, ServerResponse } from 'node:http';
import { createReadStream, existsSync, statSync } from 'node:fs';
import { dirname, extname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { handlePrivacy } from './privacy.js';
import type { PlayLog } from './play-log.js';
import type { SessionStore } from './session/store.js';

const __dirname = dirname(fileURLToPath(import.meta.url));
const PUBLIC_DIR = join(__dirname, '..', 'public');

function escapeHtml(value: string): string {
  return value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');
}

function countryLabel(code: string): string {
  if (!code || code.toLowerCase() === 'unknown') return 'Unknown';
  try {
    const display = new Intl.DisplayNames(['en'], { type: 'region' });
    return display.of(code.toUpperCase()) ?? code.toUpperCase();
  } catch {
    return code.toUpperCase();
  }
}

export function buildLandingPayload(store: SessionStore, playLog: PlayLog) {
  const sessions = store.listSessions();
  const activeSessions = sessions.length;
  const activeHosts = sessions.filter((s) => s.hostSocket != null).length;
  const plays = playLog.toLandingPayload();

  return {
    generatedAt: plays.generatedAt,
    activeSessions,
    activeHosts,
    totalPlays: plays.totalPlays,
    uniqueSongs: plays.uniqueSongs,
    topSongs: plays.topSongs,
    topArtists: plays.topArtists,
    bestSongsByCountry: plays.bestSongsByCountry,
  };
}

function renderRankedSongRows(
  songs: Array<{ title: string; artist: string; playCount: number; likes: number }>,
): string {
  if (songs.length === 0) {
    return `<li class="empty">No plays yet — start a session and press play.</li>`;
  }
  return songs
    .map((song, i) => {
      const accent = ['teal', 'coral', 'purple', 'blue'][i % 4];
      return `<li class="rank-row accent-${accent}">
  <span class="rank">${i + 1}</span>
  <span class="meta">
    <span class="title">${escapeHtml(song.title)}</span>
    <span class="artist">${escapeHtml(song.artist)}</span>
  </span>
  <span class="metric">${song.playCount}<small>plays</small></span>
</li>`;
    })
    .join('\n');
}

function renderArtistRows(
  artists: Array<{ artist: string; playCount: number; uniqueSongs: number }>,
): string {
  if (artists.length === 0) {
    return `<li class="empty">Artists will appear as songs play.</li>`;
  }
  return artists
    .map((item, i) => {
      const accent = ['coral', 'purple', 'blue', 'teal'][i % 4];
      return `<li class="rank-row accent-${accent}">
  <span class="rank">${i + 1}</span>
  <span class="meta">
    <span class="title">${escapeHtml(item.artist)}</span>
    <span class="artist">${item.uniqueSongs} song${item.uniqueSongs === 1 ? '' : 's'}</span>
  </span>
  <span class="metric">${item.playCount}<small>plays</small></span>
</li>`;
    })
    .join('\n');
}

function renderCountryBlocks(
  groups: Array<{
    countryCode: string;
    songs: Array<{ title: string; artist: string; playCount: number }>;
  }>,
): string {
  if (groups.length === 0) {
    return `<p class="empty-block">Country charts fill in once hosts share location (or record as unknown).</p>`;
  }
  return groups
    .map((group, gi) => {
      const accent = ['teal', 'coral', 'purple', 'blue'][gi % 4];
      const songs = group.songs
        .map(
          (song, i) => `<li>
  <span class="c-rank">${i + 1}</span>
  <span class="c-meta">
    <strong>${escapeHtml(song.title)}</strong>
    <em>${escapeHtml(song.artist)}</em>
  </span>
  <span class="c-plays">${song.playCount}</span>
</li>`,
        )
        .join('\n');
      return `<article class="country-panel accent-${accent}">
  <header>
    <h3>${escapeHtml(countryLabel(group.countryCode))}</h3>
    <span class="code">${escapeHtml(group.countryCode.toUpperCase())}</span>
  </header>
  <ol>${songs}</ol>
</article>`;
    })
    .join('\n');
}

export function renderLandingHtml(store: SessionStore, playLog: PlayLog): string {
  const payload = buildLandingPayload(store, playLog);
  const songRows = renderRankedSongRows(payload.topSongs);
  const artistRows = renderArtistRows(payload.topArtists);
  const countryBlocks = renderCountryBlocks(payload.bestSongsByCountry);

  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Share List</title>
  <link rel="icon" href="/public/logo.png" type="image/png" />
  <link rel="preconnect" href="https://fonts.googleapis.com" />
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
  <link href="https://fonts.googleapis.com/css2?family=Outfit:wght@500;700;800&family=Syne:wght@700;800&display=swap" rel="stylesheet" />
  <style>
    :root {
      --navy: #1a1a4e;
      --magenta: #e91e8c;
      --purple: #7b2cbf;
      --teal: #2ec4b6;
      --coral: #ff6b6b;
      --royal: #4361ee;
      --ink: #f7f2ff;
      --muted: rgba(247, 242, 255, 0.72);
      --panel: rgba(12, 10, 36, 0.42);
      --line: rgba(255, 255, 255, 0.14);
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      min-height: 100vh;
      color: var(--ink);
      font-family: Outfit, system-ui, sans-serif;
      background:
        radial-gradient(900px 500px at 85% 0%, rgba(233, 30, 140, 0.55), transparent 55%),
        radial-gradient(700px 480px at 0% 100%, rgba(67, 97, 238, 0.4), transparent 50%),
        linear-gradient(135deg, #12123a 0%, #4a1f7a 48%, #c2186a 100%);
      background-attachment: fixed;
    }
    .noise {
      pointer-events: none;
      position: fixed;
      inset: 0;
      opacity: 0.05;
      background-image: url("data:image/svg+xml,%3Csvg viewBox='0 0 200 200' xmlns='http://www.w3.org/2000/svg'%3E%3Cfilter id='n'%3E%3CfeTurbulence type='fractalNoise' baseFrequency='0.9' numOctaves='3' stitchTiles='stitch'/%3E%3C/filter%3E%3Crect width='100%25' height='100%25' filter='url(%23n)'/%3E%3C/svg%3E");
    }
    main { position: relative; max-width: 1120px; margin: 0 auto; padding: 28px 20px 64px; }
    .hero {
      display: grid;
      justify-items: center;
      text-align: center;
      gap: 14px;
      padding: 28px 12px 36px;
      animation: rise 0.7s ease both;
    }
    .logo {
      width: min(168px, 42vw);
      height: auto;
      border-radius: 28%;
      box-shadow:
        18px 18px 0 rgba(0, 0, 0, 0.18),
        0 20px 50px rgba(26, 26, 78, 0.45);
      animation: floaty 4.5s ease-in-out infinite;
    }
    .brand {
      margin: 8px 0 0;
      font-family: Syne, Outfit, sans-serif;
      font-weight: 800;
      font-size: clamp(2.4rem, 8vw, 4rem);
      letter-spacing: -0.04em;
      line-height: 0.95;
      text-shadow: 0 8px 40px rgba(0, 0, 0, 0.35);
    }
    .tag {
      max-width: 34rem;
      margin: 0;
      color: var(--muted);
      font-size: 1.05rem;
      line-height: 1.5;
    }
    .live {
      display: flex;
      flex-wrap: wrap;
      gap: 12px;
      justify-content: center;
      margin: 8px 0 28px;
      animation: rise 0.85s ease both;
    }
    .live-pill {
      min-width: 148px;
      padding: 14px 18px 12px;
      border: 1px solid var(--line);
      border-radius: 18px;
      background: var(--panel);
      backdrop-filter: blur(10px);
      text-align: left;
    }
    .live-pill .label {
      display: block;
      font-size: 0.78rem;
      text-transform: uppercase;
      letter-spacing: 0.08em;
      color: var(--muted);
    }
    .live-pill .value {
      display: block;
      margin-top: 4px;
      font-family: Syne, sans-serif;
      font-size: 2rem;
      font-weight: 800;
      line-height: 1;
    }
    .live-pill.teal .value { color: var(--teal); }
    .live-pill.coral .value { color: var(--coral); }
    .live-pill.purple .value { color: #d4a5ff; }
    .live-pill.blue .value { color: #8fb3ff; }
    .grid-2 {
      display: grid;
      gap: 20px;
      grid-template-columns: 1fr;
    }
    @media (min-width: 900px) {
      .grid-2 { grid-template-columns: 1fr 1fr; }
    }
    section {
      animation: rise 1s ease both;
    }
    section h2 {
      margin: 0 0 6px;
      font-family: Syne, sans-serif;
      font-size: 1.35rem;
      letter-spacing: -0.02em;
    }
    section .note {
      margin: 0 0 14px;
      color: var(--muted);
      font-size: 0.92rem;
    }
    .rank-list {
      list-style: none;
      margin: 0;
      padding: 0;
      max-height: 640px;
      overflow: auto;
      border-top: 1px solid var(--line);
    }
    .rank-row {
      display: grid;
      grid-template-columns: 40px 1fr auto;
      gap: 12px;
      align-items: center;
      padding: 12px 4px 12px 0;
      border-bottom: 1px solid var(--line);
    }
    .rank-row .rank {
      font-family: Syne, sans-serif;
      font-weight: 800;
      font-size: 1.1rem;
      text-align: center;
    }
    .rank-row.accent-teal .rank { color: var(--teal); }
    .rank-row.accent-coral .rank { color: var(--coral); }
    .rank-row.accent-purple .rank { color: #d4a5ff; }
    .rank-row.accent-blue .rank { color: #8fb3ff; }
    .rank-row .title {
      display: block;
      font-weight: 700;
      line-height: 1.25;
    }
    .rank-row .artist {
      display: block;
      color: var(--muted);
      font-size: 0.88rem;
      margin-top: 2px;
    }
    .rank-row .metric {
      font-variant-numeric: tabular-nums;
      font-weight: 700;
      text-align: right;
    }
    .rank-row .metric small {
      display: block;
      font-weight: 500;
      color: var(--muted);
      font-size: 0.72rem;
    }
    .empty, .empty-block {
      color: var(--muted);
      padding: 24px 4px;
    }
    .countries {
      margin-top: 36px;
      animation: rise 1.15s ease both;
    }
    .country-grid {
      display: grid;
      gap: 14px;
      grid-template-columns: repeat(auto-fill, minmax(240px, 1fr));
    }
    .country-panel {
      border: 1px solid var(--line);
      border-radius: 18px;
      background: var(--panel);
      backdrop-filter: blur(8px);
      padding: 14px 14px 8px;
      border-top-width: 4px;
    }
    .country-panel.accent-teal { border-top-color: var(--teal); }
    .country-panel.accent-coral { border-top-color: var(--coral); }
    .country-panel.accent-purple { border-top-color: #c77dff; }
    .country-panel.accent-blue { border-top-color: var(--royal); }
    .country-panel header {
      display: flex;
      justify-content: space-between;
      align-items: baseline;
      gap: 8px;
      margin-bottom: 8px;
    }
    .country-panel h3 {
      margin: 0;
      font-family: Syne, sans-serif;
      font-size: 1.05rem;
    }
    .country-panel .code {
      color: var(--muted);
      font-size: 0.75rem;
      letter-spacing: 0.06em;
    }
    .country-panel ol {
      list-style: none;
      margin: 0;
      padding: 0;
    }
    .country-panel li {
      display: grid;
      grid-template-columns: 22px 1fr auto;
      gap: 8px;
      align-items: start;
      padding: 8px 0;
      border-top: 1px solid var(--line);
    }
    .country-panel .c-rank { color: var(--muted); font-weight: 700; }
    .country-panel strong { display: block; font-size: 0.92rem; line-height: 1.25; }
    .country-panel em {
      display: block;
      font-style: normal;
      color: var(--muted);
      font-size: 0.8rem;
      margin-top: 2px;
    }
    .country-panel .c-plays {
      font-weight: 700;
      font-variant-numeric: tabular-nums;
    }
    footer {
      margin-top: 40px;
      text-align: center;
      color: var(--muted);
      font-size: 0.85rem;
    }
    @keyframes rise {
      from { opacity: 0; transform: translateY(14px); }
      to { opacity: 1; transform: none; }
    }
    @keyframes floaty {
      0%, 100% { transform: translateY(0); }
      50% { transform: translateY(-8px); }
    }
  </style>
</head>
<body>
  <div class="noise" aria-hidden="true"></div>
  <main>
    <header class="hero">
      <img class="logo" src="/public/logo.png" width="168" height="168" alt="Share List logo" />
      <h1 class="brand">Share List</h1>
      <p class="tag">Live collaborative playlists — what’s spinning right now across hosts.</p>
    </header>

    <div class="live" aria-label="Live activity">
      <div class="live-pill teal">
        <span class="label">Active sessions</span>
        <span class="value" id="stat-sessions">${payload.activeSessions}</span>
      </div>
      <div class="live-pill coral">
        <span class="label">Active hosts</span>
        <span class="value" id="stat-hosts">${payload.activeHosts}</span>
      </div>
      <div class="live-pill purple">
        <span class="label">Total plays</span>
        <span class="value" id="stat-plays">${payload.totalPlays}</span>
      </div>
      <div class="live-pill blue">
        <span class="label">Unique songs</span>
        <span class="value" id="stat-unique">${payload.uniqueSongs}</span>
      </div>
    </div>

    <div class="grid-2">
      <section>
        <h2>Top 50 songs</h2>
        <p class="note">Ranked by plays, then likes.</p>
        <ol class="rank-list" id="top-songs">${songRows}</ol>
      </section>
      <section>
        <h2>Top 50 artists</h2>
        <p class="note">Who gets the most spins worldwide.</p>
        <ol class="rank-list" id="top-artists">${artistRows}</ol>
      </section>
    </div>

    <section class="countries">
      <h2>Best songs by country</h2>
      <p class="note">Host location when available — otherwise unknown.</p>
      <div class="country-grid" id="by-country">${countryBlocks}</div>
    </section>

    <footer id="landing-footer">
      Live updates · ${escapeHtml(new Date(payload.generatedAt).toISOString())}
      · <a href="/privacy" style="color:#9ad5ff">Privacy</a>
      · <a href="https://www.youtube.com/t/terms" rel="noopener" style="color:#9ad5ff">YouTube Terms</a>
    </footer>
  </main>
  <script>
(() => {
  const ACCENTS = ['teal', 'coral', 'purple', 'blue'];
  const ACCENTS_ARTIST = ['coral', 'purple', 'blue', 'teal'];

  function esc(value) {
    return String(value ?? '')
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');
  }

  function countryLabel(code) {
    if (!code || String(code).toLowerCase() === 'unknown') return 'Unknown';
    try {
      return new Intl.DisplayNames(['en'], { type: 'region' }).of(String(code).toUpperCase())
        || String(code).toUpperCase();
    } catch {
      return String(code).toUpperCase();
    }
  }

  function renderSongs(songs) {
    if (!songs.length) {
      return '<li class="empty">No plays yet — start a session and press play.</li>';
    }
    return songs.map((song, i) => {
      const accent = ACCENTS[i % 4];
      return '<li class="rank-row accent-' + accent + '">'
        + '<span class="rank">' + (i + 1) + '</span>'
        + '<span class="meta"><span class="title">' + esc(song.title) + '</span>'
        + '<span class="artist">' + esc(song.artist) + '</span></span>'
        + '<span class="metric">' + song.playCount + '<small>plays</small></span></li>';
    }).join('');
  }

  function renderArtists(artists) {
    if (!artists.length) {
      return '<li class="empty">Artists will appear as songs play.</li>';
    }
    return artists.map((item, i) => {
      const accent = ACCENTS_ARTIST[i % 4];
      const songsLabel = item.uniqueSongs === 1 ? '1 song' : item.uniqueSongs + ' songs';
      return '<li class="rank-row accent-' + accent + '">'
        + '<span class="rank">' + (i + 1) + '</span>'
        + '<span class="meta"><span class="title">' + esc(item.artist) + '</span>'
        + '<span class="artist">' + songsLabel + '</span></span>'
        + '<span class="metric">' + item.playCount + '<small>plays</small></span></li>';
    }).join('');
  }

  function renderCountries(groups) {
    if (!groups.length) {
      return '<p class="empty-block">Country charts fill in once hosts share location (or record as unknown).</p>';
    }
    return groups.map((group, gi) => {
      const accent = ACCENTS[gi % 4];
      const songs = group.songs.map((song, i) =>
        '<li><span class="c-rank">' + (i + 1) + '</span>'
        + '<span class="c-meta"><strong>' + esc(song.title) + '</strong>'
        + '<em>' + esc(song.artist) + '</em></span>'
        + '<span class="c-plays">' + song.playCount + '</span></li>'
      ).join('');
      return '<article class="country-panel accent-' + accent + '">'
        + '<header><h3>' + esc(countryLabel(group.countryCode)) + '</h3>'
        + '<span class="code">' + esc(String(group.countryCode).toUpperCase()) + '</span></header>'
        + '<ol>' + songs + '</ol></article>';
    }).join('');
  }

  function setHtmlPreserveScroll(el, html) {
    if (!el) return;
    const top = el.scrollTop;
    el.innerHTML = html;
    el.scrollTop = top;
  }

  function apply(payload) {
    const setText = (id, value) => {
      const el = document.getElementById(id);
      if (el) el.textContent = String(value);
    };
    setText('stat-sessions', payload.activeSessions);
    setText('stat-hosts', payload.activeHosts);
    setText('stat-plays', payload.totalPlays);
    setText('stat-unique', payload.uniqueSongs);
    setHtmlPreserveScroll(document.getElementById('top-songs'), renderSongs(payload.topSongs || []));
    setHtmlPreserveScroll(document.getElementById('top-artists'), renderArtists(payload.topArtists || []));
    setHtmlPreserveScroll(document.getElementById('by-country'), renderCountries(payload.bestSongsByCountry || []));
    const footer = document.getElementById('landing-footer');
    if (footer) {
      footer.innerHTML = 'Live updates · ' + esc(new Date(payload.generatedAt).toISOString())
        + ' · <a href="/privacy" style="color:#9ad5ff">Privacy</a>'
        + ' · <a href="https://www.youtube.com/t/terms" rel="noopener" style="color:#9ad5ff">YouTube Terms</a>';
    }
  }

  async function refresh() {
    try {
      const res = await fetch('/api/landing', { cache: 'no-store' });
      if (!res.ok) return;
      apply(await res.json());
    } catch (_) { /* keep last good snapshot */ }
  }

  setInterval(refresh, 30000);
  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'visible') refresh();
  });
})();
  </script>
</body>
</html>`;
}

const MIME: Record<string, string> = {
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.webp': 'image/webp',
  '.svg': 'image/svg+xml',
  '.ico': 'image/x-icon',
};

export function handlePublicAsset(
  req: IncomingMessage,
  res: ServerResponse,
  url: URL,
): boolean {
  if (req.method !== 'GET' && req.method !== 'HEAD') return false;
  if (!url.pathname.startsWith('/public/')) return false;

  const relative = decodeURIComponent(url.pathname.slice('/public/'.length));
  if (!relative || relative.includes('..') || relative.includes('\\')) {
    res.writeHead(400);
    res.end('Bad request');
    return true;
  }

  const filePath = join(PUBLIC_DIR, relative);
  if (!filePath.startsWith(PUBLIC_DIR) || !existsSync(filePath) || !statSync(filePath).isFile()) {
    res.writeHead(404);
    res.end('Not found');
    return true;
  }

  const type = MIME[extname(filePath).toLowerCase()] ?? 'application/octet-stream';
  res.writeHead(200, {
    'Content-Type': type,
    'Cache-Control': 'public, max-age=86400',
  });
  if (req.method === 'HEAD') {
    res.end();
    return true;
  }
  createReadStream(filePath).pipe(res);
  return true;
}

export function handleLanding(
  req: IncomingMessage,
  res: ServerResponse,
  url: URL,
  store: SessionStore,
  playLog: PlayLog,
): boolean {
  if (handlePublicAsset(req, res, url)) return true;
  if (handlePrivacy(req, res, url)) return true;

  if (url.pathname === '/api/landing' && req.method === 'GET') {
    res.writeHead(200, {
      'Content-Type': 'application/json',
      'Access-Control-Allow-Origin': '*',
      'Cache-Control': 'no-store',
    });
    res.end(JSON.stringify(buildLandingPayload(store, playLog), null, 2));
    return true;
  }

  if (url.pathname === '/' && req.method === 'GET') {
    res.writeHead(200, {
      'Content-Type': 'text/html; charset=utf-8',
      'Cache-Control': 'no-store',
    });
    res.end(renderLandingHtml(store, playLog));
    return true;
  }

  return false;
}

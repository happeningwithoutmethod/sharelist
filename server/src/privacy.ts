import type { IncomingMessage, ServerResponse } from 'node:http';

/** Bump when the policy text changes in a material way (forces app re-accept). */
export const PRIVACY_POLICY_VERSION = 2;

export function renderPrivacyHtml(): string {
  const updated = '18 July 2026';
  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Privacy Policy · Share List</title>
  <link rel="icon" href="/public/logo.png" type="image/png" />
  <link rel="preconnect" href="https://fonts.googleapis.com" />
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
  <link href="https://fonts.googleapis.com/css2?family=Outfit:wght@500;700;800&family=Syne:wght@700;800&display=swap" rel="stylesheet" />
  <style>
    :root {
      --ink: #f7f2ff;
      --muted: rgba(247, 242, 255, 0.72);
      --panel: rgba(12, 10, 36, 0.55);
      --line: rgba(255, 255, 255, 0.14);
      --link: #9ad5ff;
    }
    * { box-sizing: border-box; }
    body {
      margin: 0;
      min-height: 100vh;
      color: var(--ink);
      font-family: Outfit, system-ui, sans-serif;
      line-height: 1.55;
      background:
        radial-gradient(900px 500px at 85% 0%, rgba(233, 30, 140, 0.45), transparent 55%),
        radial-gradient(700px 480px at 0% 100%, rgba(67, 97, 238, 0.35), transparent 50%),
        linear-gradient(135deg, #12123a 0%, #4a1f7a 48%, #c2186a 100%);
      background-attachment: fixed;
    }
    main {
      max-width: 720px;
      margin: 0 auto;
      padding: 32px 20px 72px;
    }
    .card {
      background: var(--panel);
      border: 1px solid var(--line);
      border-radius: 20px;
      padding: 28px 24px;
      backdrop-filter: blur(10px);
    }
    h1 {
      margin: 0 0 8px;
      font-family: Syne, Outfit, sans-serif;
      font-size: clamp(1.8rem, 5vw, 2.4rem);
      letter-spacing: -0.03em;
    }
    .meta { color: var(--muted); margin: 0 0 24px; font-size: 0.95rem; }
    h2 {
      margin: 28px 0 10px;
      font-size: 1.15rem;
      font-weight: 700;
    }
    p, li { color: var(--muted); }
    ul { padding-left: 1.2rem; }
    li { margin: 0.35rem 0; }
    a { color: var(--link); }
    .back {
      display: inline-block;
      margin-bottom: 18px;
      color: var(--link);
      text-decoration: none;
      font-weight: 600;
    }
    .back:hover { text-decoration: underline; }
    strong { color: var(--ink); font-weight: 700; }
  </style>
</head>
<body>
  <main>    
    <article class="card">
      <h1>Privacy Policy</h1>
      <p class="meta">Share List · Version ${PRIVACY_POLICY_VERSION} · Last updated ${updated}</p>

      <p>
        This Privacy Policy explains how <strong>Share List</strong>
        (“we”, “the app”, “the service”) collects, uses, and shares information
        when you use the Share List mobile app and the relay website at
        <a href="https://sharelist.servehttp.com">sharelist.servehttp.com</a>.
      </p>

      <h2>1. Who we are</h2>
      <p>
        Share List is a collaborative playlist app: one device hosts a session;
        others connect to request and vote on songs. The public website shows
        aggregated play statistics. Contact:
        <a href="mailto:happeningwithoutmethod@gmail.com">happeningwithoutmethod@gmail.com</a>.
      </p>

      <h2>2. Information we collect</h2>
      <ul>
        <li><strong>Account (optional).</strong> If you sign in with Google we receive
          your Google account identifier, display name, and email address, used to
          identify you as a session host.</li>
        <li><strong>Guest identity.</strong> If you host or connect without Google,
          we generate a local device/guest identifier stored on your device.</li>
        <li><strong>Approximate location.</strong> With permission, the host device may
          provide a country code for public play charts. If denied or unavailable,
          we store <code>unknown</code>.</li>
        <li><strong>Session content.</strong> Session names, playlists, song metadata
          (title, artist, YouTube video id / artwork URL), display names, votes,
          and connection events needed to run a live session.</li>
        <li><strong>Usage / play stats.</strong> The relay may log which songs were
          played (and host country when available) to power the public landing
          charts.</li>
        <li><strong>Technical data.</strong> IP address and standard server logs may
          be processed transiently to operate WebSocket/HTTP connections and
          protect the service.</li>
        <li><strong>Device permissions.</strong> Camera (QR join), local network /
          nearby Wi‑Fi (local mode), notifications, and Bluetooth may be used only
          for the features that need them.</li>
      </ul>

      <h2>3. How we use information</h2>
      <ul>
        <li>Run host/connector sessions and sync playlist state.</li>
        <li>Show who requested or connected (display name) to the host.</li>
        <li>Remember recent connections and saved playlists on your device.</li>
        <li>Publish aggregated “top songs / artists / by country” stats on the website.</li>
        <li>Maintain security, reliability, and abuse prevention.</li>
      </ul>

      <h2>4. YouTube and Google</h2>
      <p>
        Song search and playback use official YouTube API Services:
      </p>
      <ul>
        <li><strong>Search</strong> uses the
          <a href="https://developers.google.com/youtube/v3" rel="noopener">YouTube Data API v3</a>
          (<code>search.list</code>) via our relay. Search queries are sent to Google
          to return public video metadata (title, channel, thumbnail, video id).</li>
        <li><strong>Playback</strong> on the host uses the official YouTube
          embeddable / IFrame player. We do not download or proxy raw media files.</li>
      </ul>
      <p>
        By using YouTube features in Share List, you agree to be bound by the
        <a href="https://www.youtube.com/t/terms" rel="noopener">YouTube Terms of Service</a>.
        Google’s data practices are described in the
        <a href="https://policies.google.com/privacy" rel="noopener">Google Privacy Policy</a>.
        We do not sell your Google account data.
      </p>
      <p>
        Google Sign-In is used only for host identity (name / email / account id).
        We do not request Gmail, Drive, or other sensitive Google scopes.
      </p>

      <h2>5. Sharing</h2>
      <ul>
        <li><strong>Other session participants</strong> see playlist and display-name
          information required for the shared session.</li>
        <li><strong>Public website</strong> may show aggregated play statistics
          (song titles, artists, play counts, country labels).</li>
        <li><strong>Service providers</strong> that host our relay infrastructure may
          process connection data as needed to provide the service.</li>
        <li>We do <strong>not</strong> sell your personal information.</li>
      </ul>

      <h2>6. Retention</h2>
      <ul>
        <li>Live session data is kept while the session is active and for a short
          orphan period after the host disconnects, then discarded from the relay.</li>
        <li>Play-log aggregates may be retained on the server to power public charts.</li>
        <li>On-device data (guest id, saved playlists, privacy acceptance, last
          connections) remains until you clear app data or uninstall.</li>
      </ul>

      <h2>7. Your choices</h2>
      <ul>
        <li>Use guest mode without Google Sign-In.</li>
        <li>Deny location permission (country becomes unknown).</li>
        <li>Deny camera / nearby-device permissions (related features will be limited).</li>
        <li>Leave or end a session; clear app storage to remove local identifiers.</li>
        <li>Contact us to ask questions about this policy.</li>
      </ul>

      <h2>8. Children</h2>
      <p>
        Share List is not directed at children under 13 (or the minimum age required
        in your country). Do not use the service if you are under that age.
      </p>

      <h2>9. International processing</h2>
      <p>
        The relay may process data on servers in regions where our hosting provider
        operates. By using the service you understand that information may be
        processed outside your home country with appropriate safeguards where required.
      </p>

      <h2>10. Changes</h2>
      <p>
        We may update this policy. Material changes will update the version number
        shown above. The app may ask you to accept the new version before continuing.
      </p>

      <h2>11. Contact</h2>
      <p>
        Questions: <a href="mailto:happeningwithoutmethod@gmail.com">happeningwithoutmethod@gmail.com</a>
      </p>
    </article>
  </main>
</body>
</html>`;
}

export function handlePrivacy(
  req: IncomingMessage,
  res: ServerResponse,
  url: URL,
): boolean {
  if (url.pathname !== '/privacy' || (req.method !== 'GET' && req.method !== 'HEAD')) {
    return false;
  }

  const body = renderPrivacyHtml();
  res.writeHead(200, {
    'Content-Type': 'text/html; charset=utf-8',
    'Cache-Control': 'public, max-age=300',
  });
  if (req.method === 'HEAD') {
    res.end();
    return true;
  }
  res.end(body);
  return true;
}

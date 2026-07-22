import type { IncomingMessage, ServerResponse } from 'node:http';
import { isJoinCode, normalizeJoinCode } from './session/join-code.js';
import type { SessionStore } from './session/store.js';

function escapeHtml(value: string): string {
  return value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');
}

function corsJson(res: ServerResponse, status: number, body: unknown): void {
  res.writeHead(status, {
    'Content-Type': 'application/json',
    'Cache-Control': 'no-store',
    'Access-Control-Allow-Origin': '*',
  });
  res.end(JSON.stringify(body));
}

function renderShortCodeJoinHtml(input: {
  joinCode: string;
  sessionId: string;
  serverUrl: string;
  webLink: string;
  flutterWebLink: string;
  appLink: string;
}): string {
  const safeCode = escapeHtml(input.joinCode);
  const safeWeb = escapeHtml(input.webLink);
  const safeFlutter = escapeHtml(input.flutterWebLink);
  const safeApp = escapeHtml(input.appLink);

  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Join Share List · ${safeCode}</title>
  <style>
    :root { color-scheme: dark; font-family: system-ui, sans-serif; }
    body {
      margin: 0; min-height: 100vh; display: grid; place-items: center;
      background: #121218; color: #f4f4f8; padding: 24px;
    }
    main {
      width: min(420px, 100%); background: #1c1c26; border-radius: 16px;
      padding: 24px; box-shadow: 0 12px 40px rgba(0,0,0,.35);
    }
    h1 { margin: 0 0 8px; font-size: 1.4rem; }
    p { margin: 0 0 16px; color: #b7b7c9; line-height: 1.45; }
    .code {
      display: block; letter-spacing: 0.28em; font-size: 1.8rem; font-weight: 800;
      text-align: center; background: #0f0f16; padding: 16px; border-radius: 12px;
      margin-bottom: 16px;
    }
    a.button {
      display: block; text-align: center; text-decoration: none;
      background: #e91e8c; color: white; font-weight: 600;
      padding: 14px 16px; border-radius: 12px; margin-bottom: 10px;
    }
    a.button.secondary {
      background: transparent; border: 1px solid rgba(255,255,255,.22);
      color: #f4f4f8;
    }
  </style>
</head>
<body>
  <main>
    <h1>Join Share List</h1>
    <p>Session code</p>
    <div class="code">${safeCode}</div>
    <a class="button" href="${safeWeb}">Join in browser</a>
    <a class="button secondary" href="${safeFlutter}">Open Flutter web</a>
    <a class="button secondary" href="${safeApp}">Open in Share List app</a>
  </main>
</body>
</html>`;
}

function renderLegacyAppJoinHtml(url: URL): string {
  const sessionId =
    url.searchParams.get('session') ??
    url.searchParams.get('sessionId') ??
    '';
  const serverUrl =
    url.searchParams.get('server') ?? url.searchParams.get('serverUrl') ?? '';

  const appParams = new URLSearchParams();
  if (sessionId) appParams.set('session', sessionId);
  if (serverUrl) appParams.set('server', serverUrl);
  const appLink = `sharelist://join?${appParams.toString()}`;
  const webQuery = appParams.toString();
  const webLink = `/web/${webQuery ? `?${webQuery}` : ''}`;
  const flutterWebLink = `/app/${webQuery ? `?${webQuery}` : ''}`;
  const safeSession = escapeHtml(sessionId || 'unknown');
  const safeAppLink = escapeHtml(appLink);
  const safeWebLink = escapeHtml(webLink);
  const safeFlutterLink = escapeHtml(flutterWebLink);

  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Join Share List</title>
  <style>
    :root { color-scheme: dark; font-family: system-ui, sans-serif; }
    body {
      margin: 0; min-height: 100vh; display: grid; place-items: center;
      background: #121218; color: #f4f4f8; padding: 24px;
    }
    main {
      width: min(420px, 100%); background: #1c1c26; border-radius: 16px;
      padding: 24px; box-shadow: 0 12px 40px rgba(0,0,0,.35);
    }
    h1 { margin: 0 0 8px; font-size: 1.4rem; }
    p { margin: 0 0 16px; color: #b7b7c9; line-height: 1.45; }
    code {
      display: block; word-break: break-all; background: #0f0f16;
      padding: 10px 12px; border-radius: 8px; margin-bottom: 16px; font-size: .85rem;
    }
    a.button {
      display: block; text-align: center; text-decoration: none;
      background: #e91e8c; color: white; font-weight: 600;
      padding: 14px 16px; border-radius: 12px; margin-bottom: 10px;
    }
    a.button.secondary {
      background: transparent; border: 1px solid rgba(255,255,255,.22);
      color: #f4f4f8;
    }
    .hint { margin-top: 8px; font-size: .85rem; }
  </style>
</head>
<body>
  <main>
    <h1>Join Share List</h1>
    <p>Session:</p>
    <code>${safeSession}</code>
    <a class="button" href="${safeWebLink}">Join in browser</a>
    <a class="button secondary" href="${safeFlutterLink}">Open Flutter web</a>
    <a class="button secondary" href="${safeAppLink}">Open in Share List app</a>
    <p class="hint">Use the browser on any device, or open the app if installed.</p>
  </main>
</body>
</html>`;
}

function renderMissingCodeHtml(code: string): string {
  const safe = escapeHtml(code);
  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Session not found</title>
  <style>
    :root { color-scheme: dark; font-family: system-ui, sans-serif; }
    body {
      margin: 0; min-height: 100vh; display: grid; place-items: center;
      background: #121218; color: #f4f4f8; padding: 24px;
    }
    main {
      width: min(420px, 100%); background: #1c1c26; border-radius: 16px;
      padding: 24px;
    }
  </style>
</head>
<body>
  <main>
    <h1>Session not found</h1>
    <p>No active session uses code <strong>${safe}</strong>. Ask the host for a new code.</p>
    <p><a href="/web/" style="color:#9ad5ff">Open Share List web</a>
      · <a href="/app/" style="color:#9ad5ff">Flutter web</a></p>
  </main>
</body>
</html>`;
}

/**
 * Handles short-code join pages + JSON resolve API.
 * Returns true when the request was handled.
 */
export function handleJoinRoutes(
  req: IncomingMessage,
  res: ServerResponse,
  url: URL,
  store: SessionStore,
  serverPublicUrl: string,
): boolean {
  // CORS preflight for resolve API (web clients).
  if (
    req.method === 'OPTIONS' &&
    (url.pathname.startsWith('/api/join') ||
      url.pathname.startsWith('/api/host/join-code'))
  ) {
    res.writeHead(204, {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type',
      'Access-Control-Max-Age': '86400',
    });
    res.end();
    return true;
  }

  // Host lookup: sessionId + sessionToken → joinCode (for UI recovery).
  if (url.pathname === '/api/host/join-code' && req.method === 'GET') {
    const sessionId = (url.searchParams.get('sessionId') ?? '').trim();
    const sessionToken = (url.searchParams.get('sessionToken') ?? '').trim();
    if (!sessionId || !sessionToken) {
      corsJson(res, 400, { error: 'sessionId and sessionToken are required' });
      return true;
    }
    const session = store.getSession(sessionId);
    if (!session || session.status === 'ended') {
      corsJson(res, 404, { error: 'Session not found' });
      return true;
    }
    if (session.sessionToken !== sessionToken) {
      corsJson(res, 403, { error: 'Invalid session token' });
      return true;
    }
    corsJson(res, 200, {
      joinCode: session.joinCode,
      sessionId: session.id,
      serverUrl: serverPublicUrl,
    });
    return true;
  }

  const apiMatch = url.pathname.match(/^\/api\/join\/([^/]+)\/?$/i);
  if (apiMatch && req.method === 'GET') {
    const code = normalizeJoinCode(decodeURIComponent(apiMatch[1] ?? ''));
    if (!isJoinCode(code)) {
      corsJson(res, 400, { error: 'Invalid join code' });
      return true;
    }
    const session = store.getSessionByJoinCode(code);
    if (!session || session.status === 'ended') {
      corsJson(res, 404, { error: 'Session not found' });
      return true;
    }
    corsJson(res, 200, {
      joinCode: session.joinCode,
      sessionId: session.id,
      serverUrl: serverPublicUrl,
      sessionName: session.stateSnapshot.sessionName,
    });
    return true;
  }

  if ((url.pathname === '/join' || url.pathname.startsWith('/join/')) && req.method === 'GET') {
    const segment = url.pathname.startsWith('/join/')
      ? decodeURIComponent(url.pathname.slice('/join/'.length).split('/')[0] ?? '')
      : '';
    const code = normalizeJoinCode(segment);

    if (isJoinCode(code)) {
      const session = store.getSessionByJoinCode(code);
      if (!session || session.status === 'ended') {
        res.writeHead(404, {
          'Content-Type': 'text/html; charset=utf-8',
          'Cache-Control': 'no-store',
        });
        res.end(renderMissingCodeHtml(code));
        return true;
      }

      const webParams = new URLSearchParams({
        session: session.id,
        server: serverPublicUrl,
        code: session.joinCode,
      });
      const webLink = `/web/?${webParams.toString()}`;
      const flutterWebLink = `/app/?${webParams.toString()}`;
      const appParams = new URLSearchParams({
        session: session.id,
        server: serverPublicUrl,
      });
      const appLink = `sharelist://join?${appParams.toString()}`;

      res.writeHead(200, {
        'Content-Type': 'text/html; charset=utf-8',
        'Cache-Control': 'no-store',
      });
      res.end(
        renderShortCodeJoinHtml({
          joinCode: session.joinCode,
          sessionId: session.id,
          serverUrl: serverPublicUrl,
          webLink,
          flutterWebLink,
          appLink,
        }),
      );
      return true;
    }

    // Legacy app deep-link bridge: /join?session=&server=
    res.writeHead(200, {
      'Content-Type': 'text/html; charset=utf-8',
      'Cache-Control': 'no-store',
    });
    res.end(renderLegacyAppJoinHtml(url));
    return true;
  }

  return false;
}

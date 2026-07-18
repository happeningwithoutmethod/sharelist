import type { IncomingMessage, ServerResponse } from 'node:http';
import { timingSafeEqual } from 'node:crypto';

const COOKIE_NAME = 'sharelist_relay_passkey';

function configuredPasskey(): string | undefined {
  const value = process.env.RELAY_INFO_PASSKEY?.trim();
  return value && value.length > 0 ? value : undefined;
}

function safeEqual(a: string, b: string): boolean {
  const left = Buffer.from(a);
  const right = Buffer.from(b);
  if (left.length !== right.length) return false;
  return timingSafeEqual(left, right);
}

function parseCookies(header: string | undefined): Record<string, string> {
  if (!header) return {};
  const out: Record<string, string> = {};
  for (const part of header.split(';')) {
    const eq = part.indexOf('=');
    if (eq <= 0) continue;
    const key = part.slice(0, eq).trim();
    const value = decodeURIComponent(part.slice(eq + 1).trim());
    out[key] = value;
  }
  return out;
}

function extractPresentedPasskey(req: IncomingMessage, url: URL): string | undefined {
  const auth = req.headers.authorization;
  if (auth?.startsWith('Bearer ')) {
    return auth.slice('Bearer '.length).trim();
  }
  if (auth?.startsWith('Basic ')) {
    try {
      const decoded = Buffer.from(auth.slice('Basic '.length), 'base64').toString('utf8');
      const colon = decoded.indexOf(':');
      return colon >= 0 ? decoded.slice(colon + 1) : decoded;
    } catch {
      return undefined;
    }
  }

  const cookies = parseCookies(req.headers.cookie);
  if (cookies[COOKIE_NAME]) return cookies[COOKIE_NAME];

  const fromQuery = url.searchParams.get('passkey')?.trim();
  if (fromQuery) return fromQuery;

  return undefined;
}

export function verifyRelayPasskey(presented: string | undefined): boolean {
  const expected = configuredPasskey();
  if (!expected || !presented) return false;
  return safeEqual(presented, expected);
}

export function isRelayInfoAuthorized(req: IncomingMessage, url: URL): boolean {
  return verifyRelayPasskey(extractPresentedPasskey(req, url));
}

export function relayInfoPasskeyConfigured(): boolean {
  return configuredPasskey() != null;
}

export function setRelayInfoPasskeyCookie(res: ServerResponse, passkey: string): void {
  const secure = process.env.PUBLIC_HTTPS_URL?.startsWith('https') ? '; Secure' : '';
  res.setHeader(
    'Set-Cookie',
    `${COOKIE_NAME}=${encodeURIComponent(passkey)}; Path=/relay/info; HttpOnly; SameSite=Strict; Max-Age=2592000${secure}`,
  );
}

export function clearRelayInfoPasskeyCookie(res: ServerResponse): void {
  res.setHeader(
    'Set-Cookie',
    `${COOKIE_NAME}=; Path=/relay/info; HttpOnly; SameSite=Strict; Max-Age=0`,
  );
}

export function sendUnauthorized(
  res: ServerResponse,
  options: { htmlLogin?: boolean; realm?: string } = {},
): void {
  if (options.htmlLogin) {
    res.writeHead(401, {
      'Content-Type': 'text/html; charset=utf-8',
      'Cache-Control': 'no-store',
    });
    res.end(renderRelayLoginHtml(Boolean(configuredPasskey())));
    return;
  }

  res.writeHead(401, {
    'Content-Type': 'application/json',
    'WWW-Authenticate': `Basic realm="${options.realm ?? 'Share List Relay'}"`,
    'Cache-Control': 'no-store',
  });
  res.end(JSON.stringify({ error: 'Unauthorized' }));
}

function renderRelayLoginHtml(configured: boolean): string {
  const message = configured
    ? 'Enter the relay info passkey from the server .env file.'
    : 'RELAY_INFO_PASSKEY is not set on the server.';
  return `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Relay info — sign in</title>
  <style>
    :root { color-scheme: dark; font-family: system-ui, sans-serif; }
    body { margin: 0; min-height: 100vh; display: grid; place-items: center; background: #0f1419; color: #e7eef7; }
    form { width: min(380px, 92vw); background: #1a222c; border: 1px solid #2a3542; border-radius: 16px; padding: 24px; }
    h1 { margin: 0 0 8px; font-size: 1.25rem; }
    p { color: #8b9bb0; margin: 0 0 16px; line-height: 1.45; }
    input { width: 100%; box-sizing: border-box; padding: 12px 14px; border-radius: 10px; border: 1px solid #2a3542; background: #121820; color: inherit; }
    button { margin-top: 12px; width: 100%; padding: 12px 14px; border: 0; border-radius: 10px; background: #6c5ce7; color: white; font-weight: 650; cursor: pointer; }
  </style>
</head>
<body>
  <form method="post" action="/relay/info/login">
    <h1>Relay admin</h1>
    <p>${message}</p>
    <input type="password" name="passkey" placeholder="Passkey" autocomplete="current-password" ${configured ? 'required' : 'disabled'} />
    <button type="submit" ${configured ? '' : 'disabled'}>Unlock</button>
  </form>
</body>
</html>`;
}

export async function readPasskeyFromPost(req: IncomingMessage): Promise<string | undefined> {
  const chunks: Buffer[] = [];
  for await (const chunk of req) {
    chunks.push(Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk));
  }
  const body = Buffer.concat(chunks).toString('utf8');
  const params = new URLSearchParams(body);
  return params.get('passkey')?.trim() || undefined;
}

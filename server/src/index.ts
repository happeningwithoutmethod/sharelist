import fs from 'node:fs';
import http from 'node:http';
import https from 'node:https';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import type { IncomingMessage, ServerResponse } from 'node:http';
import { WebSocketServer } from 'ws';
import { handleDashboard } from './dashboard.js';
import { handleJoinRoutes } from './join.js';
import { handleLanding } from './landing.js';
import { handleMusicApi } from './music/youtube.js';
import { PlayLog } from './play-log.js';
import { SessionStore } from './session/store.js';
import { WebSocketHandler } from './ws/handler.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const serverRoot = path.resolve(__dirname, '..');

function envFlag(name: string, fallback: boolean): boolean {
  const raw = process.env[name];
  if (raw == null || raw.trim() === '') return fallback;
  return !['0', 'false', 'no', 'off'].includes(raw.trim().toLowerCase());
}

function resolvePath(value: string | undefined): string | undefined {
  if (!value?.trim()) return undefined;
  return path.isAbsolute(value) ? value : path.resolve(serverRoot, value);
}

const HOST = process.env.HOST ?? '0.0.0.0';
const HOSTNAME = process.env.HOSTNAME ?? 'localhost';
const ENABLE_HTTP = envFlag('ENABLE_HTTP', true);
const ENABLE_HTTPS = envFlag('ENABLE_HTTPS', false);
const PORT = Number(process.env.PORT ?? 3000);
const HTTPS_PORT = Number(process.env.HTTPS_PORT ?? 3443);
const SSL_CERT_PATH = resolvePath(process.env.SSL_CERT_PATH);
const SSL_KEY_PATH = resolvePath(process.env.SSL_KEY_PATH);

const PUBLIC_HTTP_URL =
  process.env.PUBLIC_HTTP_URL ??
  (PORT === 80 ? `http://${HOSTNAME}` : `http://${HOSTNAME}:${PORT}`);
const PUBLIC_HTTPS_URL =
  process.env.PUBLIC_HTTPS_URL ??
  (HTTPS_PORT === 443 ? `https://${HOSTNAME}` : `https://${HOSTNAME}:${HTTPS_PORT}`);
const PUBLIC_URL =
  process.env.PUBLIC_URL ??
  (ENABLE_HTTPS ? PUBLIC_HTTPS_URL.replace(/^https/i, 'wss') : PUBLIC_HTTP_URL.replace(/^http/i, 'ws'));

const store = new SessionStore();
const playLog = new PlayLog();
const handler = new WebSocketHandler(store, PUBLIC_URL, playLog);

async function handleRequest(req: IncomingMessage, res: ServerResponse): Promise<void> {
  const host = req.headers.host ?? `${HOSTNAME}:${PORT}`;
  const proto =
    (req.socket as { encrypted?: boolean }).encrypted ||
    req.headers['x-forwarded-proto'] === 'https'
      ? 'https'
      : 'http';
  const url = new URL(req.url ?? '/', `${proto}://${host}`);

  if (url.pathname === '/health') {
    res.writeHead(200, {
      'Content-Type': 'application/json',
      'Access-Control-Allow-Origin': '*',
    });
    res.end(
      JSON.stringify({
        status: 'ok',
        http: ENABLE_HTTP,
        https: ENABLE_HTTPS,
      }),
    );
    return;
  }

  if (handleLanding(req, res, url, store, playLog)) {
    return;
  }

  if (handleJoinRoutes(req, res, url, store, PUBLIC_URL)) {
    return;
  }

  if (handleDashboard(req, res, url, store, playLog)) {
    return;
  }

  if (await handleMusicApi(req, res, url)) {
    return;
  }

  res.writeHead(404);
  res.end('Not found');
}

function attachWebSocket(server: http.Server | https.Server): WebSocketServer {
  const wss = new WebSocketServer({ server, path: '/session' });
  wss.on('connection', (socket) => {
    handler.handleConnection(socket);
  });
  return wss;
}

function listen(
  server: http.Server | https.Server,
  port: number,
  label: string,
): Promise<void> {
  return new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(port, HOST, () => {
      server.off('error', reject);
      console.log(`${label} listening on ${HOST}:${port}`);
      resolve();
    });
  });
}

async function main(): Promise<void> {
  if (!ENABLE_HTTP && !ENABLE_HTTPS) {
    throw new Error('Enable at least one of ENABLE_HTTP or ENABLE_HTTPS');
  }

  const servers: Array<http.Server | https.Server> = [];
  let httpStarted = false;
  let httpsStarted = false;

  if (ENABLE_HTTP) {
    const httpServer = http.createServer((req, res) => {
      void handleRequest(req, res);
    });
    attachWebSocket(httpServer);
    await listen(httpServer, PORT, 'HTTP');
    servers.push(httpServer);
    httpStarted = true;
  }

  if (ENABLE_HTTPS) {
    if (!SSL_CERT_PATH || !SSL_KEY_PATH) {
      console.warn(
        'ENABLE_HTTPS=true but SSL_CERT_PATH/SSL_KEY_PATH are missing — skipping HTTPS',
      );
    } else if (!fs.existsSync(SSL_CERT_PATH) || !fs.existsSync(SSL_KEY_PATH)) {
      console.warn(
        `ENABLE_HTTPS=true but cert/key not found — skipping HTTPS\n  cert: ${SSL_CERT_PATH}\n  key:  ${SSL_KEY_PATH}\n  Run:  .\\generate-certs.ps1`,
      );
    } else {
      const httpsServer = https.createServer(
        {
          cert: fs.readFileSync(SSL_CERT_PATH),
          key: fs.readFileSync(SSL_KEY_PATH),
        },
        (req, res) => {
          void handleRequest(req, res);
        },
      );
      attachWebSocket(httpsServer);
      await listen(httpsServer, HTTPS_PORT, 'HTTPS');
      servers.push(httpsServer);
      httpsStarted = true;
    }
  }

  if (!httpStarted && !httpsStarted) {
    throw new Error('No listeners started — check ENABLE_HTTP / ENABLE_HTTPS and TLS certs');
  }

  console.log(`Hostname: ${HOSTNAME}`);
  console.log(`Advertised WebSocket URL: ${PUBLIC_URL}/session`);
  if (httpStarted) {
    console.log(`HTTP dashboard: ${PUBLIC_HTTP_URL}/`);
    console.log(`HTTP music API: ${PUBLIC_HTTP_URL}/api/music/search?q=test`);
    console.log(`HTTP play log:  ${PUBLIC_HTTP_URL}/api/plays`);
    console.log(`WS endpoint:    ${PUBLIC_HTTP_URL.replace(/^http/i, 'ws')}/session`);
  }
  if (httpsStarted) {
    console.log(`HTTPS dashboard: ${PUBLIC_HTTPS_URL}/`);
    console.log(`HTTPS music API: ${PUBLIC_HTTPS_URL}/api/music/search?q=test`);
    console.log(`HTTPS play log:  ${PUBLIC_HTTPS_URL}/api/plays`);
    console.log(`WSS endpoint:    ${PUBLIC_HTTPS_URL.replace(/^https/i, 'wss')}/session`);
  }

  const shutdown = () => {
    for (const server of servers) {
      server.close();
    }
    process.exit(0);
  };
  process.on('SIGINT', shutdown);
  process.on('SIGTERM', shutdown);
}

main().catch((error) => {
  console.error(error instanceof Error ? error.message : error);
  process.exit(1);
});

# HTTPS for Share List (nginx + Let's Encrypt)

nginx terminates TLS on ports **80** / **443** for one hostname:

| Path | Backend |
|------|---------|
| `https://sharelist.servehttp.com/` | Relay API + WebSocket + landing (`share-list:3000`) |
| `https://sharelist.servehttp.com/web/` | React web client (`share-list-client:80`) |
| `https://sharelist.servehttp.com/app/` | Flutter web client (`share-list-web:80`) |
| `https://sharelist.servehttp.com/join/…` | Join bridge / short codes (`share-list:3000`) |

```
Internet
   │
   ├─ :80  ──► nginx (ACME + redirect to HTTPS)
   └─ :443 ──► nginx (Let's Encrypt TLS)
                  ├─ /web/  → share-list-client
                  ├─ /app/  → share-list-web
                  └─ /      → share-list:3000
```

## Prerequisites

1. Public IP reachable on **80** and **443**.
2. DNS **A** record: `sharelist.servehttp.com` → that IP.
3. Docker Engine + Compose v2.
4. `ACME_EMAIL` set in `server/.env`.

> Free ports 80/443 on the host (stop other web servers first).

## 1. Configure `.env`

```env
HOSTNAME=sharelist.servehttp.com
ACME_EMAIL=you@example.com

ENABLE_HTTP=true
ENABLE_HTTPS=false

PUBLIC_HTTP_URL=http://sharelist.servehttp.com
PUBLIC_HTTPS_URL=https://sharelist.servehttp.com
PUBLIC_URL=wss://sharelist.servehttp.com

# Optional — Web OAuth client ID baked into the React client image
# GOOGLE_WEB_CLIENT_ID=xxxxx.apps.googleusercontent.com
```

`ENABLE_HTTPS=false` — TLS is handled by nginx, not the Node process.

## 2. Start the stack

```bash
cd server
docker compose up -d --build
```

Until certificates exist, nginx proxies **HTTP only** on port 80.

## 3. Obtain Let's Encrypt certificate

```bash
docker compose --profile certs run --rm certbot-init
docker compose restart nginx
```

After restart, nginx enables HTTPS on **443** and redirects HTTP → HTTPS.

Renewal runs in `certbot-renew` (every 12h). After a renew:

```bash
docker compose restart nginx
```

## 4. Verify

```text
https://sharelist.servehttp.com/          → relay landing / API
wss://sharelist.servehttp.com/session     → WebSocket
https://sharelist.servehttp.com/web/      → React web app
https://sharelist.servehttp.com/app/      → Flutter web app
https://sharelist.servehttp.com/join/ABC123 → join bridge
```

```bash
curl -I https://sharelist.servehttp.com/health
curl -I https://sharelist.servehttp.com/web/
curl -I https://sharelist.servehttp.com/app/
```

## Flutter web

Deployed by Compose as `share-list-web` at `/app/`. Local image build:

```bash
docker build -f apps/mobile/Dockerfile.web -t share-list-web \
  --build-arg BASE_HREF=/app/ \
  --build-arg GOOGLE_WEB_CLIENT_ID=your-web-client-id.apps.googleusercontent.com \
  .
```

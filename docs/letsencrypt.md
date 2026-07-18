# Let's Encrypt HTTPS for Share List server

This guide sets up **automatic HTTPS** for the Share List relay using
[Let's Encrypt](https://letsencrypt.org/) via [Caddy](https://caddyserver.com/)
in Docker Compose.

Caddy obtains and renews certificates for you. The Node app speaks plain HTTP
on the internal Docker network; Caddy terminates TLS on ports **80** and **443**.

## Architecture

```
Internet
   │
   ├─ :80  ──► Caddy (HTTP-01 challenge + redirect to HTTPS)
   └─ :443 ──► Caddy (Let's Encrypt TLS)
                  │
                  └─ reverse_proxy ──► share-list:3000
                                       (HTTP + WebSocket /session)
```

## Prerequisites

1. A **public IP** reachable on ports **80** and **443** (not blocked by firewall/ISP).
2. A **DNS A (or AAAA) record** for your hostname pointing at that IP.
   Example: `sharelist.servehttp.com` → your server.
3. Docker Engine + Docker Compose v2.
4. An email address for Let's Encrypt expiry notices.

> Ports 80 and 443 must be free on the host. Stop any other web server or
> tunnel (nginx, Apache, servehttp, etc.) that is already bound to them.

## 1. Configure environment

From the `server/` directory:

```bash
cp .env.example .env
```

Edit `.env` and set at least:

```env
HOSTNAME=sharelist.example.com
ACME_EMAIL=you@example.com

ENABLE_HTTP=true
ENABLE_HTTPS=false

PUBLIC_HTTP_URL=http://sharelist.example.com
PUBLIC_HTTPS_URL=https://sharelist.example.com
PUBLIC_URL=wss://sharelist.example.com
```

Notes:

- `HOSTNAME` must match the DNS name clients use.
- `ENABLE_HTTPS=false` — TLS is handled by Caddy, not the Node process.
- `PUBLIC_URL` should use `wss://` so the app advertises a secure WebSocket URL
  (QR codes, share links, connectors).

Also keep the mobile app `ServerConfig` / join origin aligned with this hostname
(`apps/mobile/lib/config/server_config.dart`).

## 2. Open firewall ports

Allow inbound TCP **80** and **443** (and UDP **443** if you want HTTP/3).

Examples:

```bash
# ufw
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow 443/udp
sudo ufw reload
```

## 3. Start the stack

```bash
cd server
docker compose up -d --build
```

Services:

| Service       | Role                                      |
|---------------|-------------------------------------------|
| `share-list`  | Relay API + WebSocket (internal `:3000`)  |
| `caddy`       | Public HTTP/HTTPS + Let's Encrypt         |

Check status:

```bash
docker compose ps
docker compose logs -f caddy
docker compose logs -f share-list
```

On first start, Caddy contacts Let's Encrypt, completes the HTTP-01 challenge
on port 80, and stores certificates in the `caddy-data` volume.

## 4. Verify

```bash
curl -I https://YOUR_HOSTNAME/health
curl -I https://YOUR_HOSTNAME/join?session=test
```

You should see a valid certificate for `YOUR_HOSTNAME` (not self-signed).

In a browser, open `https://YOUR_HOSTNAME/` for the public stats landing page.
The admin relay dashboard is at `https://YOUR_HOSTNAME/relay/info` and requires `RELAY_INFO_PASSKEY` from `.env`.

## 5. Renewal

No cron job is required. Caddy renews Let's Encrypt certificates automatically
and reloads without downtime.

Certificates live in the Docker volume `caddy-data`. Back it up if you care
about preserving ACME account state across reinstalls:

```bash
docker volume inspect share-list_caddy-data
```

## Troubleshooting

### Certificate not issued

1. Confirm DNS: `dig +short YOUR_HOSTNAME` returns this server's public IP.
2. Confirm port 80 is reachable from the internet (not only localhost).
3. Check Caddy logs: `docker compose logs caddy`.
4. Ensure `ACME_EMAIL` is set to a real address.
5. Let's Encrypt **rate limits** failed attempts — wait or use the
   [staging environment](https://letsencrypt.org/docs/staging-environment/)
   while testing (see below).

### Staging certificates (testing)

To avoid production rate limits while debugging DNS/firewall, temporarily use
Let's Encrypt staging by adding to `Caddyfile` inside the global block:

```caddyfile
{
	email {$ACME_EMAIL}
	acme_ca https://acme-staging-v02.api.letsencrypt.org/directory
}
```

Browsers will warn about the staging cert. Remove `acme_ca` for production and
restart:

```bash
docker compose up -d --force-recreate caddy
```

If Caddy cached a bad cert, clear the data volume (this drops issued certs):

```bash
docker compose down
docker volume rm share-list_caddy-data
docker compose up -d
```

(Volume name may include a project prefix — check with `docker volume ls`.)

### WebSocket / app cannot connect

- App and share links must use `wss://YOUR_HOSTNAME` (not `ws://` or `:3443`).
- Caddy proxies WebSockets automatically; no extra config is needed.
- Health check: `https://YOUR_HOSTNAME/health` should return JSON `{"status":"ok",...}`.

### Running without Let's Encrypt (local / LAN)

For local self-signed TLS **without** Caddy, see `generate-certs.ps1` and set
`ENABLE_HTTPS=true` with `SSL_CERT_PATH` / `SSL_KEY_PATH`. That path is for
direct Node HTTPS (e.g. development), not production Let's Encrypt.

To run only the app container without Caddy:

```bash
docker compose stop caddy
docker compose publish  # not needed — instead map ports manually, e.g.:
docker compose run --service-ports ...
```

Prefer this override when developing locally without public DNS — publish the
app port yourself:

```bash
docker compose up -d share-list
docker compose port share-list  # or add ports: ["3000:3000"] temporarily
```

## Files

| File | Purpose |
|------|---------|
| `server/docker-compose.yml` | `share-list` + `caddy` services |
| `server/Caddyfile` | Hostname, ACME email, reverse proxy |
| `server/.env` | `HOSTNAME`, `ACME_EMAIL`, public URLs |
| `server/Dockerfile` | Builds the Share List relay image |

## Security notes

- Keep `ACME_EMAIL` private in `.env` (gitignored).
- Do not expose Node's port `3000` on the public internet when Caddy is in use.
- After changing `HOSTNAME`, update DNS first, then recreate Caddy so it can
  request a certificate for the new name.

# Share List

Collaborative music playlist app: a **host** plays YouTube tracks and **connectors** join via QR / code / link to request songs and vote.

Production: [https://sharelist.servehttp.com](https://sharelist.servehttp.com)

| Path | What |
|------|------|
| `/` | Relay landing, API, WebSocket, join bridge |
| `/web/` | React web client |
| `/app/` | Flutter web client |
| `/apk` | Latest Android APK download |

## Structure

```
share-list/
├── apps/mobile/          # Flutter app (Android / iOS / web → /app/)
├── client/               # React Vite client → /web/
├── packages/
│   ├── shared_models/    # Shared Dart models and wire messages
│   └── music_providers/  # MusicProvider + YouTube search
├── server/               # Node.js WebSocket relay + docker compose
├── docs/                 # Deploy, OAuth, YouTube API, iOS, etc.
├── build-apk.ps1         # Bump version + build release APK → build/
├── copy-apk.ps1          # SCP latest APK to Ubuntu host as sharelist-latest.apk
└── copy-env.ps1          # SCP server/.env + client/.env to Ubuntu host
```

## Modes

- **Host** — Start a session (Google Sign-In or guest), play music, manage playlist / approvals.
- **Connect** — Join via QR, 6-character code, or share link. Request songs and vote.

The relay routes WebSocket traffic and keeps an orphaned session alive for **~30 minutes** after the host disconnects so host and connectors can reconnect.

## Local development

### Relay

```bash
cd server
cp .env.example .env   # edit as needed
npm install
npm run dev
```

- HTTP: `http://localhost:3000`
- WebSocket: `ws://localhost:3000/session`

Android emulator → host machine: set `PUBLIC_URL=ws://10.0.2.2:3000`.

### React client

```bash
cd client
cp .env.example .env
npm install
npm run dev
```

Open http://localhost:5173/web/

```env
VITE_WS_URL=wss://sharelist.servehttp.com
VITE_API_ORIGIN=https://sharelist.servehttp.com
VITE_GOOGLE_CLIENT_ID=your-web-client-id.apps.googleusercontent.com
```

### Flutter app

```bash
cd apps/mobile
flutter pub get
flutter run
```

Google Sign-In setup: [docs/google.md](docs/google.md). iOS ship notes: [docs/ios-app-instructions.md](docs/ios-app-instructions.md).

## Production (Docker)

Stack lives in `server/docker-compose.yml` (nginx TLS, relay, React client, Flutter web, certbot). Full guide: [docs/letsencrypt.md](docs/letsencrypt.md).

```bash
cd server
cp .env.example .env
cp ../client/.env.example ../client/.env
# edit both .env files

docker compose up -d --build
docker compose --profile certs run --rm certbot-init
docker compose restart nginx
```

**Host-mounted env (no image rebuild to change secrets):**

| Host file | Container |
|-----------|-----------|
| `server/.env` | `share-list` → `/app/.env` |
| `client/.env` | `share-list-client` → `/config/.env` → `/web/env.js` |

After editing env on the server:

```bash
docker compose up -d --force-recreate share-list share-list-client
```

YouTube Data API key (`YOUTUBE_API_KEY`): [docs/youtube_data_api.md](docs/youtube_data_api.md).

## Deploy helpers (Windows → Ubuntu)

Defaults: `hwm@192.168.1.222`, repo `~/dev/sharelist`.

```powershell
.\build-apk.ps1          # release APK → build/share-list-0.0.N-release.apk
.\copy-apk.ps1           # → …/server/public/apk/sharelist-latest.apk
.\copy-env.ps1           # server/.env + client/.env → Ubuntu host
.\copy-env.ps1 -ServerOnly
.\copy-env.ps1 -ClientOnly
```

APK is served at https://sharelist.servehttp.com/apk (nginx bind-mount of `server/public/apk/`).

## Docs

| Doc | Topic |
|-----|--------|
| [docs/letsencrypt.md](docs/letsencrypt.md) | HTTPS + Docker routes |
| [docs/google.md](docs/google.md) | Google OAuth (Android / iOS / web) |
| [docs/youtube_data_api.md](docs/youtube_data_api.md) | Search API key |
| [docs/ios-app-instructions.md](docs/ios-app-instructions.md) | iOS build & App Store |
| [client/README.md](client/README.md) | React client details |

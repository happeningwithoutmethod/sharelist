# Share List

Collaborative music playlist app where a **host** plays music and **connectors** join via QR code to request songs and vote.

## Structure

```
share-list/
├── apps/mobile/          # Flutter app (host + connect modes)
├── client/               # React web client (served at /web/)
├── packages/
│   ├── shared_models/    # Shared Dart models and wire messages
│   └── music_providers/  # MusicProvider interface + YouTube Music
├── server/               # Node.js WebSocket relay server
└── README.md
```

## Quick start

### Relay server

```bash
cd server
npm install
npm run dev
```

Server listens on `http://localhost:3000` with WebSocket at `ws://localhost:3000/session`.

For Android emulator, set `PUBLIC_URL=ws://10.0.2.2:3000` when starting the server.

### React web client

```bash
cd client
npm install   # or yarn
npm run dev
```

Open http://localhost:5173/web/. Production image is `share-list-client` in `server/docker-compose.yml`.

### Mobile app

```bash
cd apps/mobile
flutter pub get
flutter run
```

Configure Google Sign-In OAuth client IDs in:
- `android/app/src/main/res/values/strings.xml`
- iOS `Info.plist` / GoogleService-Info.plist (for production)

## Modes

- **Host mode** — Google Sign-In required. Starts session, plays music, manages playlist.
- **Connect mode** — Scan host QR code. Optional Google login for display name. Request songs and vote.

## Architecture

The relay server routes WebSocket messages between host and connectors and caches session state for 30-minute host reconnect. All playlist logic runs on the host device.

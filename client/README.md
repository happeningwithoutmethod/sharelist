# Share List React web client

Served in production at `https://sharelist.servehttp.com/web/`.

## Local development

```bash
cd client
cp .env.example .env   # optional
npm install
npm run dev
```

Open http://localhost:5173/web/

Env (`.env` or `.env.local`):

```env
VITE_WS_URL=wss://sharelist.servehttp.com
VITE_API_ORIGIN=https://sharelist.servehttp.com
VITE_GOOGLE_CLIENT_ID=your-web-client-id.apps.googleusercontent.com
```

Google Sign-In needs a **Web application** OAuth client with JavaScript origin
`http://localhost:5173` (dev) and `https://sharelist.servehttp.com` (prod).

## Docker

Built by `server/docker-compose.yml` as `share-list-client`.

Runtime config is read from the **host file** `client/.env` (bind-mounted at
`/config/.env`). On start, the entrypoint writes `/web/env.js` — edit the host
`.env` and restart the container (no image rebuild) to apply changes:

```bash
cd client && cp .env.example .env   # once
# edit client/.env
cd ../server && docker compose up -d --force-recreate share-list-client
```

The relay server similarly mounts `server/.env` at `/app/.env` and loads it with
Node `--env-file=.env`.

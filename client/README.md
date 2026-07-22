# Share List React web client

Served in production at `https://sharelist.servehttp.com/web/`.

## Local development

```bash
cd client
npm install
npm run dev
```

Open http://localhost:5173/web/

Optional env (`.env.local`):

```env
VITE_WS_URL=wss://sharelist.servehttp.com
VITE_API_ORIGIN=https://sharelist.servehttp.com
VITE_GOOGLE_CLIENT_ID=your-web-client-id.apps.googleusercontent.com
```

Google Sign-In needs a **Web application** OAuth client with JavaScript origin
`http://localhost:5173` (dev) and `https://sharelist.servehttp.com` (prod).

## Docker

Built by `server/docker-compose.yml` as `share-list-client`.

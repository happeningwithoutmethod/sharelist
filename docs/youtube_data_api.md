# YouTube Data API v3 — Share List setup

Share List searches songs with the official **YouTube Data API v3**
[`search.list`](https://developers.google.com/youtube/v3/docs/search/list)
method. Host **playback** uses the official YouTube IFrame / embeddable player
(`youtube_player_iframe`).

## Architecture

| Surface | Behavior |
|---------|----------|
| Central relay `/api/music/search` | Calls Data API with `YOUTUBE_API_KEY` from `server/.env` |
| App (host / connect) | Prefer `RemoteMusicProvider` → relay search (key stays on server) |
| Local-mode relay | Proxies search to `JOIN_ORIGIN` / `ServerConfig.joinOrigin`; optional local key fallback via `--dart-define=YOUTUBE_API_KEY=...` |
| Direct `YouTubeMusicProvider` | Data API only; needs `YOUTUBE_API_KEY` dart-define (dev/offline) |

## Google Cloud setup

1. Open [Google Cloud Console](https://console.cloud.google.com/) and create/select a project.
2. Enable **YouTube Data API v3** (APIs & Services → Library).
3. Create an **API key** (APIs & Services → Credentials).
4. Restrict the key:
   - API restriction: **YouTube Data API v3** only
   - Application restriction: prefer **IP addresses** of your relay (production)
5. Put the key in `server/.env`:

```env
YOUTUBE_API_KEY=your-key-here
```

6. Redeploy the relay so the container picks up the env var:

```bash
cd server
docker compose up -d --build
```

Do **not** commit real API keys. Keep production keys out of the mobile APK when possible (relay-only).

## Quotas

- Default project quota historically included a shared **10,000 units/day** pool; `search.list` historically cost **100 units** per call (~100 searches/day).
- As of mid-2026, Google also documents a dedicated **Search Queries** bucket for `search.list` (on the order of **~100 calls/day** by default). Confirm current numbers in Cloud Console → APIs & Services → YouTube Data API v3 → Quotas.
- This app requests `maxResults=20`, `type=video`, `safeSearch=moderate` per search.
- If you outgrow the default, use the [YouTube API Services Audit and Quota Extension form](https://support.google.com/youtube/contact/yt_api_form). Increases are manual and not guaranteed.

Monitor usage in Cloud Console. Return clear errors from `/api/music/search` when the key is missing (HTTP 503) or Google returns quota/errors.

## Required disclosures (API Client)

YouTube API Clients must:

1. Link the [YouTube Terms of Service](https://www.youtube.com/t/terms)
2. Link the [Google Privacy Policy](https://policies.google.com/privacy)
3. State that YouTube features bind users to YouTube’s Terms
4. Publish a privacy policy describing YouTube/Google data use

**Share List surfaces:**

| Place | What |
|-------|------|
| `https://sharelist.servehttp.com/privacy` | Policy §4 (Data API search + iframe playback + ToS binding) |
| App first-run `/privacy` | Accept gate; mentions YouTube ToS |
| Home → Settings | Privacy Policy, YouTube Terms, Google Privacy Policy |
| Landing footer | Privacy + YouTube Terms |

Privacy policy version is **2** (`PRIVACY_POLICY_VERSION` / `privacyPolicyVersion`) after the Data API wording change — existing installs re-accept once.

## Reviewer / Play Console summary

Use **`docs/play_reviewer_youtube.md`** for Play Console notes and YouTube API audits
(paste-ready paragraph, flow, disclosures, what we do not do).

**Model (short):** Collaborative playlist session. Host plays videos only through the
official YouTube embeddable player. Song discovery uses YouTube Data API v3
`search.list` with a project-owned API key on the relay. No raw media download
or CDN audio proxy.

## Optional local / CI dart-define

```bash
flutter run --dart-define=YOUTUBE_API_KEY=dev-restricted-key
```

Prefer a separate restricted key for any client-side use; production hosts should rely on the relay.

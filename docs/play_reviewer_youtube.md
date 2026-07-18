# Share List — YouTube / Play reviewer model

**Product:** Share List — collaborative playlist sessions (one host, multiple connectors).  
**Audience:** Google Play reviewers and YouTube API Services auditors.  
**Last updated:** 18 July 2026  

This document describes **how Share List uses YouTube**. It is the chosen compliance model for store and API review.

---

## One-paragraph summary (paste into Play Console notes)

Share List is a collaborative playlist app. The host device plays songs only through the **official YouTube embeddable / IFrame player**. Song search uses the official **YouTube Data API v3** (`search.list`) with a Google Cloud project API key on our relay server. The app does **not** download, extract, or proxy raw YouTube audio/video files, and does **not** use undocumented YouTube InnerTube or third-party stream extractors. Users are shown our privacy policy and links to the YouTube Terms of Service and Google Privacy Policy. Privacy policy: https://sharelist.servehttp.com/privacy

---

## Product flow (what reviewers will see)

1. **First launch** — User must accept the privacy policy (in-app WebView of the published policy).
2. **Home** — Choose Host Mode or Connect Mode. Settings expose Privacy Policy, YouTube Terms of Service, and Google Privacy Policy.
3. **Host** — Starts a session; builds a playlist by searching songs; plays the current track in an embedded YouTube player on the Control tab (and a mini player on other tabs when a track is loaded).
4. **Connect** — Joins via QR / link; can search and request songs / vote. Connectors do not drive the YouTube player; the host does.

---

## YouTube usage model

| Function | Official API / surface | What we send / show | What we do **not** do |
|----------|------------------------|---------------------|------------------------|
| **Search** | [YouTube Data API v3 `search.list`](https://developers.google.com/youtube/v3/docs/search/list) | Query string → public metadata (video id, title, channel, thumbnail) | No scraping, no InnerTube, no unofficial search clients |
| **Playback** | [YouTube IFrame / embeddable player](https://developers.google.com/youtube/iframe_api_reference) via `youtube_player_iframe` | Cue/play by video id inside Google’s player UI | No `just_audio`/CDN URL playback, no audio download, no media proxy |
| **Identity (optional)** | Google Sign-In (`email`, `profile`) | Host display name / account id for session identity | No YouTube Data write scopes; Sign-In is not used to unlock streams |

### Where the API key lives

- Production search runs on the **relay** (`/api/music/search`) using `YOUTUBE_API_KEY` from server configuration.
- The mobile app prefers calling that relay endpoint so the production key is not required inside the APK.
- Local (LAN) hosting proxies search to the same central origin when possible.

Engineering setup (quotas, key restrictions): see `docs/youtube_data_api.md`.

---

## Disclosures & policy URLs

| Requirement | Where it appears |
|-------------|------------------|
| App privacy policy | https://sharelist.servehttp.com/privacy |
| YouTube Terms of Service | https://www.youtube.com/t/terms — linked from privacy §4, app Settings, landing footer; first-run copy states YouTube features bind users to YouTube’s Terms |
| Google Privacy Policy | https://policies.google.com/privacy — linked from privacy §4 and app Settings |
| Contact | happeningwithoutmethod@gmail.com (stated on privacy page) |

Privacy policy section **4 (YouTube and Google)** explicitly describes Data API search, iframe playback, and ToS binding.

---

## Permissions that may appear during review

| Permission / capability | Why |
|-------------------------|-----|
| Camera | Scan QR to join a session |
| Approximate location (optional) | Host country label for public play charts; deny → `unknown` |
| Nearby devices / local network | Optional LAN (“local mode”) hosting |
| Notifications | Session / app notifications where used |
| Internet | Relay WebSocket + YouTube player / search |

Google Sign-In is **optional** for hosting (guest host is supported).

---

## Explicit non-goals (common rejection triggers)

Share List does **not**:

- Extract or proxy YouTube media streams (no ANDROID_VR / Innertube player resolve, no `/api/music/audio`)
- Bypass the YouTube player, ads, or content protections
- Mix non-YouTube results into YouTube-branded search in a misleading way
- Claim to be YouTube, YouTube Music, or an official Google product
- Use YouTube content offline as downloaded files

---

## How to verify quickly

1. Open Host Mode → add a song via search → confirm playback is inside the YouTube iframe (YouTube chrome / branding visible).
2. Open Home → Settings → open **Privacy Policy**, **YouTube Terms of Service**, and **Google Privacy Policy**.
3. Confirm https://sharelist.servehttp.com/privacy loads and mentions YouTube Data API + embeddable player.
4. (API audit) Confirm server search is `googleapis.com/youtube/v3/search` only — see `server/src/music/youtube.ts`.

---

## Related docs

| Doc | Purpose |
|-----|---------|
| `docs/youtube_data_api.md` | Cloud project key, quotas, deploy |
| `docs/google_terms.md` | Engineering compliance assessment |
| `docs/todo_playstore.md` | Full Play Console checklist |
| `docs/google.md` | Google Sign-In / OAuth setup |

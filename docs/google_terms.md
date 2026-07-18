# Google terms & policies assessment — Share List

**Date:** 2026-07-18 (re-evaluated after YouTube Data API v3 search)  
**Scope:** Whether the current Share List client + relay conflict with Google / YouTube contractual terms  
**Status:** **Aligned for YouTube search + playback** (Data API v3 + official iframe), subject to keeping project credentials, quotas, and disclosures current; Google Sign-In production setup still incomplete  

> This is an engineering compliance review against publicly published Google/YouTube terms, **not legal advice**. Policies change; re-check before Play submission or commercial launch.

---

## Executive verdict

| Area | Verdict | Severity |
|------|---------|----------|
| YouTube Terms of Service — **host playback** | **Aligned** (official iframe player on Android/iOS/web) | — |
| YouTube Terms of Service — **search** | **Aligned** (YouTube Data API v3 `search.list`) | — |
| YouTube API Services ToS / Developer Policies | **Aligned** if key/quotas/disclosures stay in place | Ongoing |
| Google Sign-In / OAuth / API User Data Policy | **Mostly OK**; incomplete production OAuth setup | Medium |
| Google Fonts (landing page) | **OK** (standard webfont use) | Low |
| Google Play policies | Separate checklist — see `docs/todo_playstore.md` | High (store) |

**Bottom line:** Host **playback** uses Google’s embeddable YouTube player. **Search** uses YouTube Data API v3 with a project API key on the relay. Stream-extraction / ANDROID_VR audio-proxy code has been removed. Setup guide: `docs/youtube_data_api.md`.

---

## What the product does with Google services

### A. YouTube music search & playback (core product)

| Path | Mechanism | Files |
|------|-----------|--------|
| Search (relay) | YouTube Data API v3 `search.list` (`YOUTUBE_API_KEY`) | `server/src/music/youtube.ts` |
| Search (app) | Prefer `RemoteMusicProvider` → relay; optional direct Data API via dart-define | `remote_music_provider.dart`, `youtube_music_provider.dart` |
| Local relay search | Proxies to central `JOIN_ORIGIN` `/api/music/search` | `local_music_api.dart` |
| **Playback (host, all platforms)** | Official **YouTube IFrame Player** (`youtube_player_iframe`) | `playback_service.dart`, `host_shell.dart` |

### B. Google Sign-In

- Package: `google_sign_in`
- Scopes: `email`, `profile` only
- Used for host identity (`account.id` / Google sub), display name, email
- Access token may still be retained on `AuthUser`; host playback/search do **not** need it
- Setup notes: `docs/google.md`

### C. Other Google surfaces

- Public landing loads fonts from `fonts.googleapis.com` / `fonts.gstatic.com`
- No Google Ads SDK, no Maps SDK

---

## 1. YouTube Terms of Service

**Source:** [YouTube Terms of Service](https://www.youtube.com/t/terms)

### Assessment vs Share List

| Behavior | ToS fit |
|----------|---------|
| Host play via embeddable YouTube iframe | **Aligned** |
| Search via YouTube Data API v3 | **Aligned** (authorized API Client use) |
| Legacy raw audio CDN / ANDROID_VR proxy | **Removed** |

**Conclusion:** Playback and search are on documented YouTube surfaces.

---

## 2. YouTube API Services Terms & Developer Policies

**Sources:**

- [YouTube API Services Terms of Service](https://developers.google.com/youtube/terms/api-services-terms-of-service)
- [YouTube API Services Developer Policies](https://developers.google.com/youtube/terms/developer-policies)

### Current posture

| Requirement | Share List |
|-------------|------------|
| Documented APIs only | Data API v3 search + IFrame Player |
| Project credentials / quotas | `YOUTUBE_API_KEY` on relay; monitor Cloud Console quotas |
| Privacy policy + YouTube ToS link + Google Privacy Policy | `/privacy` §4; app settings; landing footer |
| Users bound by YouTube ToS | Stated in privacy policy + first-run copy |
| No undocumented Innertube / scrape / media proxy | Removed |

**Conclusion:** Search + playback path matches the intended API Client model. Keep disclosures and quota monitoring current.

---

## 3. Google Sign-In

Identity-only scopes remain appropriate. Finish production OAuth clients (see `docs/google.md` / Play checklist). Privacy policy describes Google account use.

---

## 4. Google Fonts

Landing page CSS loads Outfit / Syne from Google Fonts CDNs. Standard webfont use; no conflict identified.

---

## 5. Interaction with Google Play policies

Play review is separate from YouTube ToS. Document the Data API + iframe model for reviewers (`docs/youtube_data_api.md`, `docs/todo_playstore.md`).

---

## 6. Severity matrix (actionable)

### Done for YouTube API compliance path

1. Official iframe playback  
2. Data API v3 search + project key on relay  
3. Privacy / YouTube ToS / Google Privacy links  
4. Removed stream/ANDROID_VR proxy stack  

### High — keep healthy in production

5. Set and restrict `YOUTUBE_API_KEY`; redeploy relay  
6. Watch Search Queries / daily quotas; request extension if needed  
7. Keep privacy version + disclosures in sync when YouTube use changes  

### Medium — Google identity hygiene

8. Align “Premium YouTube Music” copy with reality (identity-only today)  
9. Finish OAuth production setup (`docs/google.md`)  

### Low / OK

10. Google Fonts on the landing page  
11. Guest hosting without Google  

---

## 7. Compliant direction (current)

| Option | Status |
|--------|--------|
| **A. Official YouTube player + Data API v3 search** | **Implemented** |
| **B. Licensed music catalog** | Not used |
| **C. User-supplied URLs only** | Not used |

---

## 8. Evidence index (code)

| Finding | Evidence |
|---------|----------|
| Data API search (server) | `server/src/music/youtube.ts` (`search.list`) |
| Data API search (app optional) | `packages/music_providers/lib/src/youtube_music_provider.dart` |
| Host playback = official iframe | `apps/mobile/lib/services/playback_service.dart` |
| Privacy + ToS disclosures | `server/src/privacy.ts`, app Settings, landing footer |
| Setup / quotas | `docs/youtube_data_api.md` |
| Reviewer model (Play / API audit) | `docs/play_reviewer_youtube.md` |
| Google Sign-In scopes | `apps/mobile/lib/services/auth_service.dart` |

---

## 9. Summary answer

**Does the app currently avoid breaking Google’s YouTube API terms for search and playback?**  
**Yes, for the implemented model** — Data API v3 search + official iframe playback, with published privacy/ToS links — **provided** `YOUTUBE_API_KEY` is configured, quotas are respected, and disclosures stay accurate.

Google Sign-In production setup and general Play Console checklist items remain separate work.

# Play Store readiness — Share List (Android)

**Status:** Not ready for Play upload  
**Package:** `com.happeningwithoutmethod.sharelist`  
**Version audited:** `0.0.9+9`  
**Last reviewed:** 2026-07-18

Use this as a working checklist. Items marked **blocker** must be fixed before submitting; others can ship in a follow-up release if Console allows.

---

## Already in good shape

- Unique application ID / namespace match
- `targetSdk` / `compileSdk` 36 (meets current Play API bar)
- `minSdk` 24
- 64-bit ABIs included (`arm64-v8a` + 32-bit)
- Release builds use R8 shrinking; not debuggable
- Launcher icon present (`@mipmap/launcher_icon`)
- No `ACCESS_BACKGROUND_LOCATION` (location is one-shot country lookup)
- `NEARBY_WIFI_DEVICES` marked `neverForLocation`
- No in-app purchases / Play Billing surface
- Guest host path (Google account not always required)
- Custom-scheme deep link `sharelist://join` works without Digital Asset Links

---

## Blockers

### 1. Release signing still uses the debug keystore
**Where:** `apps/mobile/android/app/build.gradle.kts` (`signingConfig = signingConfigs.getByName("debug")`)  
**Need:**
- [ ] Create a dedicated upload keystore (keep offline / password manager)
- [ ] Wire `signingConfigs.release` via `key.properties` (gitignored)
- [ ] Enroll in **Play App Signing**
- [ ] Register a **release** Android OAuth client with the upload/App Signing SHA-1 (see `docs/google.md`)

### 2. No Privacy Policy (or Terms) URL
Play Console requires a privacy policy when you collect account data, location, etc.  
**Current:** served at `https://sharelist.servehttp.com/privacy`; first-run acceptance in the app.  
**Need:**
- [x] Publish Privacy Policy covering Google account, approximate location → country, session/playlist UGC, device identifiers, server play-log stats
- [ ] Publish Terms of Service (strongly recommended with UGC)
- [x] Add policy URL on the public landing / in-app (settings + first-run gate)
- [ ] Add policy URL in Play Console

### 3. Data safety form not preparable / undocumented
Data currently processed:
- Google account (id, name, email, token)
- Approximate location → country code for host play stats
- Session / playlist / display-name UGC
- Local device / guest IDs

**Need:**
- [ ] Complete Play **Data safety** questionnaire accurately
- [ ] Declare Location, Camera, and account-related collection/sharing
- [ ] Document whether country/play stats are shared publicly on the landing page

### 4. Global cleartext traffic enabled
**Where:** `AndroidManifest.xml` → `android:usesCleartextTraffic="true"`  
Needed for local LAN `ws://` / `http://` relay, but applies app-wide.  
**Need:**
- [ ] Replace with a scoped `networkSecurityConfig` (cleartext only for local/debug / RFC1918 if required)
- [ ] Keep production relay on HTTPS / WSS only

### 5. Sensitive permissions without prominent disclosure / contextual requests
**Declared:** camera, fine/coarse location, Bluetooth, notifications, FGS media playback, nearby Wi‑Fi.  
**Gaps:**
- [ ] In-app disclosure **before** location (country for public charts) and camera (QR join)
- [ ] Request camera when opening the scanner, not at cold start
- [ ] Request location when starting host mode (already closer), with clear copy if denied → `unknown`
- [ ] Fill Play Console permission declarations / photos & videos / location questionnaires as prompted

### 6. Store listing assets missing
**Need:**
- [ ] High-res icon **512×512** (Play asset; preferably square without baked corner mask)
- [ ] Feature graphic **1024×500**
- [ ] Phone screenshots (min 2; ideally 4–8) — host, connect, playlist, QR
- [ ] Short description (≤80 chars) and full description
- [ ] Optional: tablet / TV screenshots if you claim those form factors

### 7. YouTube / music search policy risk (high)
Host **playback** uses the official YouTube iframe player.  
**Search** uses YouTube Data API v3 (`search.list`) via the relay (`YOUTUBE_API_KEY`).  
**Need:**
- [x] Host playback via official YouTube IFrame Player (Android/iOS/web)
- [x] Remove unused stream-extraction / ANDROID_VR proxy code paths
- [x] Replace search with **YouTube Data API v3** (project key, quotas, privacy/ToS links)
- [x] Document the chosen model for reviewers (`docs/play_reviewer_youtube.md`)
- [ ] Set production `YOUTUBE_API_KEY` in `server/.env` and redeploy relay
- [ ] Confirm Cloud Console quotas / request extension if search volume needs it

### 8. Release Google Sign-In not finished
**Where:** `docs/google.md`, `auth_service.dart`  
**Need:**
- [ ] Android OAuth client for **release** SHA-1 (and Play App Signing cert SHA-1 if different)
- [ ] Web client ID as `serverClientId` (recommended)
- [ ] Move OAuth consent screen out of Testing / add production users as required
- [ ] Verify sign-in on a release/`appbundle` build before submit

---

## Should-fix (before or soon after first submit)

### Adaptive icons & branding
- [ ] Generate adaptive icon (`mipmap-anydpi-v26`) — currently raster-only launcher mipmaps
- [ ] Optional `android:roundIcon`
- [ ] Branded splash (today `launch_background.xml` is blank white)

### App Links verification
HTTPS `/join` filters exist but are **not** verified Digital Asset Links.  
- [ ] Host `https://sharelist.servehttp.com/.well-known/assetlinks.json`
- [ ] Add `android:autoVerify="true"` on the HTTPS intent-filter
- [ ] Drop the plain `http` App Link filter for production
- [ ] Verify with `adb shell pm get-app-links …`

### Foreground service hygiene
- [ ] App declares `FOREGROUND_SERVICE_MEDIA_PLAYBACK` but playback is in-process via `just_audio` — remove unused permission **or** implement a proper media FGS if you need background playback guarantees
- [ ] Geolocator may merge a location FGS — declare `FOREGROUND_SERVICE_LOCATION` only if you actually start that service; prefer keeping location as a one-shot without FGS

### Backup / sensitive local data
Session tokens and host Google sub live in SharedPreferences with default backup.  
- [ ] Add `android:allowBackup` / data extraction rules that exclude session secrets

### Content rating & UGC
App has collaborative playlists, display names, song requests (UGC + music).  
- [ ] Complete IARC content rating questionnaire
- [ ] Prepare UGC answers (moderation / reporting / block story — even if minimal for v1)
- [ ] Do **not** enroll in Designed for Families unless intentional

### Versioning / packaging
- [ ] Prefer AAB (`flutter build appbundle`) over raw APK for Play
- [ ] Consider bumping past `0.0.x` for first public listing
- [ ] Confirm 16 KB page-size / native lib requirements if Play Console flags them for your NDK/Flutter version

---

## Console checklist (non-code)

- [ ] Developer account (paid) in good standing
- [ ] App access instructions for reviewers (how to host/join a session; test accounts)
- [ ] Contact email / support URL
- [ ] Categories, tags, target audience, news-app / COVID declarations as applicable
- [ ] Countries / pricing (free)
- [ ] Ads declaration (none, if true)
- [ ] Government apps / financial features declarations (N/A)

---

## Suggested order of work

1. Privacy Policy + ToS + landing links  
2. Release signing + Play App Signing + release OAuth SHA-1  
3. Cleartext scoping + Data safety form  
4. Permission disclosures / contextual prompts  
5. Decide YouTube/compliance approach  
6. Listing assets + content rating  
7. App Links + adaptive icons + FGS cleanup  
8. Internal testing track → closed → production  

---

## Key file references

| Topic | Path |
|-------|------|
| Package / signing | `apps/mobile/android/app/build.gradle.kts` |
| Permissions / cleartext / links | `apps/mobile/android/app/src/main/AndroidManifest.xml` |
| Version | `apps/mobile/pubspec.yaml` |
| Google OAuth notes | `docs/google.md` |
| Location → country | `apps/mobile/lib/services/host_country.dart` |
| Google sign-in | `apps/mobile/lib/services/auth_service.dart` |
| Music / YouTube provider | `packages/music_providers/` |

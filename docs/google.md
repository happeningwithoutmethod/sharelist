Here’s a practical Google Sign-In setup guide for **Share List**.

Your app uses `google_sign_in` with scopes `email` and `profile`. Package IDs:

| Platform | ID |
|----------|-----|
| Android | `com.happeningwithoutmethod.sharelist` |
| iOS | `com.sharelist.shareList` |

---

## 1. Create a Google Cloud project

1. Open [Google Cloud Console](https://console.cloud.google.com/)
2. Create a project (e.g. **Share List**)
3. Go to **APIs & Services → OAuth consent screen**
4. Choose **External** (unless you only use Workspace accounts)
5. Fill in app name, support email, developer contact
6. Add scopes: `email`, `profile`, `openid`
7. Add your Google account as a **Test user** while the app is in Testing

---

## 2. Create OAuth client IDs

Go to **APIs & Services → Credentials → Create credentials → OAuth client ID**.

### A. Web client (required for Flutter web + recommended for Android)

Create type **Web application**.

**Authorized JavaScript origins** (for browser / Flutter web sign-in):

- `https://sharelist.servehttp.com`
- `http://localhost` (and any `http://localhost:PORT` you use with `flutter run -d chrome`)

**Authorized redirect URIs** can stay empty for the GIS popup flow used by `google_sign_in` on web.

Copy the **Web client ID** (looks like `xxxxx.apps.googleusercontent.com`).

### B. Android client

1. Type: **Android**
2. Package name: `com.happeningwithoutmethod.sharelist`
3. SHA-1 fingerprint (debug):

```powershell
cd C:\Dev\share-list\apps\mobile\android
.\gradlew signingReport
```

Or with the Java keytool (default debug keystore):

```powershell
keytool -list -v -alias androiddebugkey -keystore "$env:USERPROFILE\.android\debug.keystore" -storepass android -keypass android
```

Copy the **SHA-1** into the Android OAuth client.

Create a **separate** Android client later for release with your release keystore SHA-1.

### C. iOS client (if you run on iPhone/simulator)

1. Type: **iOS**
2. Bundle ID: `com.sharelist.shareList`
3. Copy the iOS **Client ID**

---

## 3. Wire it into the Flutter app

### Web (Flutter web / “JS” build)

Pass the **Web client ID** at build or run time:

```powershell
flutter run -d chrome --dart-define=GOOGLE_WEB_CLIENT_ID=YOUR_WEB_CLIENT_ID.apps.googleusercontent.com
```

Or when building the optional Docker web image:

```bash
docker build -f apps/mobile/Dockerfile.web \
  --build-arg GOOGLE_WEB_CLIENT_ID=YOUR_WEB_CLIENT_ID.apps.googleusercontent.com \
  -t share-list-web .
```

Without this, web sign-in fails with a cryptic null-check (`Null check operator used on a null value`).

Also ensure the Cloud Console Web client lists your site under **Authorized JavaScript origins**.

### Android

Usually **no** `google-services.json` is required for basic `google_sign_in` if the OAuth Android client matches package + SHA-1.

If sign-in still fails with `ApiException: 10` (DEVELOPER_ERROR), double-check:

- Package name exact match: `com.happeningwithoutmethod.sharelist`
- SHA-1 matches the keystore you actually run with (`flutter run` = debug)
- You’re using the same Google Cloud project as the consent screen

Optional but recommended: pass the same **Web client ID** (done automatically when `GOOGLE_WEB_CLIENT_ID` is set) — see [`auth_service.dart`](apps/mobile/lib/services/auth_service.dart).

### iOS

1. Open `ios/Runner/Info.plist`
2. Add a URL scheme from the **reversed** iOS client ID  

   If client ID is `123456789-abc.apps.googleusercontent.com`, reversed is `com.googleusercontent.apps.123456789-abc`

Example:

```xml
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleTypeRole</key>
    <string>Editor</string>
    <key>CFBundleURLSchemes</key>
    <array>
      <string>com.googleusercontent.apps.123456789-abc</string>
    </array>
  </dict>
</array>
```

3. Optionally set:

```xml
<key>GIDClientID</key>
<string>YOUR_IOS_CLIENT_ID.apps.googleusercontent.com</string>
```

Then rebuild:

```powershell
cd C:\Dev\share-list\apps\mobile
flutter clean
flutter run
```

---

## 4. What works where

| Where you run the app | Google Sign-In |
|----------------------|----------------|
| Android emulator / device | Supported (main path) |
| iOS simulator / device | Supported after iOS client + URL scheme |
| Flutter web (Chrome) | Supported with Web OAuth client + `GOOGLE_WEB_CLIENT_ID` |
| Windows desktop (`flutter run -d windows`) | **Not supported** by `google_sign_in` the same way |

If you’re testing on **Windows desktop**, Host Mode will open the start screen, but Sign in with Google will fail. Use Android, iOS, or Flutter web.

---

## 5. Quick verification checklist

1. Consent screen published or your account is a **Test user**
2. Android OAuth client: package `com.happeningwithoutmethod.sharelist` + correct SHA-1
3. Web OAuth client: JS origins include your host (and localhost for dev)
4. App rebuilt after credential / dart-define changes
5. Tap **Host Mode → Sign in with Google** → account picker appears

---

## 6. Common errors

| Error | Cause |
|-------|--------|
| `Null check operator used on a null value` (web) | Missing `GOOGLE_WEB_CLIENT_ID` / Web client ID |
| `ApiException: 10` | Wrong package name or SHA-1 |
| `ApiException: 12500` | Misconfigured OAuth / Play Services |
| Sign-in cancelled immediately | Consent screen / test user missing |
| Works on one machine, not another | Different debug keystore SHA-1 — add that SHA-1 too |
| GIS / origin errors in browser console | Web client missing this site’s JavaScript origin |

---

## 7. About YouTube Music Premium

Current code only requests `email` and `profile` and stores the Google **access token**. That identifies the host; it does **not** by itself unlock full YouTube Music Premium APIs (those need unofficial/cookie flows or other scopes that Google often won’t grant to third-party apps).

For Host Mode today, Google login mainly identifies the host for session create/reconnect. Access tokens are not used for playback or search.

Song search uses **YouTube Data API v3** on the relay (`YOUTUBE_API_KEY`). See `docs/youtube_data_api.md`.

# iOS app — create, build, and deploy

Guide for shipping the Share List Flutter app (`apps/mobile`) to an iPhone/iPad and the App Store.

| | |
|--|--|
| **Display name** | Share List |
| **Bundle ID** | `com.sharelist.shareList` |
| **Min iOS** | 13.0 (`IPHONEOS_DEPLOYMENT_TARGET`) |
| **Version** | From `apps/mobile/pubspec.yaml` (`version: x.y.z+build`) |
| **Project** | `apps/mobile/ios/Runner.xcworkspace` |
| **Privacy policy** | https://sharelist.servehttp.com/privacy |
| **Production relay** | `wss://sharelist.servehttp.com` |

Related docs: [`google.md`](google.md) (OAuth), [`todo_playstore.md`](todo_playstore.md) (Android checklist — many App Store themes overlap).

---

## Requirements

### Hardware / OS

- A **Mac** with a recent **macOS** (Apple does not allow building iOS apps on Windows/Linux alone).
- **Xcode** from the Mac App Store (current stable).
- Optional but recommended: a physical **iPhone** or **iPad** for TestFlight / device testing.
- Apple silicon or Intel Mac both work; use the Xcode that matches your Mac.

### Accounts

1. **Apple Developer Program** membership ([developer.apple.com](https://developer.apple.com/programs/)) — required for TestFlight and App Store (paid annual).
2. Free Apple ID can install to your own device for short-lived debug builds, but **not** for App Store / TestFlight.
3. **Google Cloud** project with an **iOS** OAuth client (see [`google.md`](google.md)) if you want Google Sign-In on iOS.

### Software on the Mac

```bash
# Flutter (stable)
flutter doctor

# Confirm iOS toolchain
flutter doctor -v
# Expect: Xcode, CocoaPods, connected device or simulator
```

- Install **CocoaPods** if Flutter doctor asks (`sudo gem install cocoapods` or Homebrew).
- Open once: `open apps/mobile/ios/Runner.xcworkspace` so Xcode can install platforms/simulators.

### What the app uses on iOS (declare honestly in App Store Connect)

| Capability | Why | Info.plist key |
|------------|-----|----------------|
| Camera | Scan host QR to join | `NSCameraUsageDescription` |
| Location (when in use) | Host country for public play charts | `NSLocationWhenInUseUsageDescription` |
| Bluetooth | Audio routing to speakers/headphones | `NSBluetoothAlwaysUsageDescription` / Peripheral |
| Background audio | Keep host playback going | `UIBackgroundModes` → `audio` |
| Deep link | `sharelist://join?…` | `CFBundleURLTypes` → scheme `sharelist` |

Already present in [`apps/mobile/ios/Runner/Info.plist`](../apps/mobile/ios/Runner/Info.plist).

---

## 1. One-time Apple / Xcode setup

1. Enroll in the **Apple Developer Program**.
2. In Xcode → **Settings → Accounts**, add your Apple ID.
3. Open the iOS project:

```bash
cd /path/to/share-list/apps/mobile
open ios/Runner.xcworkspace
```

Use **`.xcworkspace`**, not `.xcodeproj` (CocoaPods).

4. Select the **Runner** target → **Signing & Capabilities**:
   - Team: your Personal Team or Organization
   - Bundle Identifier: **`com.sharelist.shareList`** (must match App Store Connect and Google iOS OAuth client)
   - Enable **Automatically manage signing** for development, or use your Distribution cert / profiles for release

5. If the bundle ID is already taken on another team, you must either use that team or change the ID everywhere (Xcode, Google iOS client, any Universal Links later).

---

## 2. Google Sign-In on iOS

Follow the iOS section in [`google.md`](google.md). Summary:

1. Google Cloud → **Credentials → OAuth client ID → iOS**
2. Bundle ID: `com.sharelist.shareList`
3. Copy the iOS client ID
4. Add a **URL scheme** = the **reversed** client ID  
   Example: `123-abc.apps.googleusercontent.com` → `com.googleusercontent.apps.123-abc`
5. Add it under `CFBundleURLTypes` / `CFBundleURLSchemes` in `Info.plist` **in addition to** the existing `sharelist` scheme (do not remove `sharelist` — join deep links need it)
6. Optional: `GIDClientID` = the iOS client ID string

Then:

```bash
cd apps/mobile
flutter clean
flutter pub get
cd ios && pod install && cd ..
flutter run -d <ios-device-or-simulator>
```

---

## 3. Local development

```bash
cd apps/mobile
flutter pub get
cd ios && pod install && cd ..

# List devices
flutter devices

# Run on simulator or USB device
flutter run -d iphone
```

Default relay is configured for production (`sharelist.servehttp.com`). For a local relay, use your existing dart-defines / server config patterns (see app `ServerConfig` / mode picker).

**Deep link test:** open Safari on device and navigate to a `sharelist://join?session=…&server=…` URL, or use the HTTPS join bridge (`https://sharelist.servehttp.com/join/…`) which offers “Open in Share List app”.

---

## 4. Build a release (IPA)

Bump version in `apps/mobile/pubspec.yaml` when shipping (e.g. `0.0.26+26` → name `+` build number).

### A. Archive from Flutter CLI

```bash
cd apps/mobile
flutter build ipa
```

Output is under `build/ios/ipa/`. Upload that IPA with **Transporter** or `xcrun altool` / `xcodebuild` as preferred.

### B. Archive from Xcode (common for first App Store submit)

```bash
cd apps/mobile
flutter build ios --release
open ios/Runner.xcworkspace
```

Then: **Product → Archive** → **Distribute App** → App Store Connect / TestFlight.

Signing must use a **Distribution** certificate and an App Store provisioning profile for `com.sharelist.shareList`.

---

## 5. App Store Connect & TestFlight

1. Go to [App Store Connect](https://appstoreconnect.apple.com/)
2. **My Apps → + → New App**
   - Platform: iOS
   - Name: Share List
   - Bundle ID: `com.sharelist.shareList` (create the ID under Certificates, Identifiers & Profiles if needed)
   - SKU: e.g. `sharelist-ios`
3. Upload the build (Xcode Organizer or Transporter)
4. After processing, add the build to **TestFlight**
5. Add internal/external testers; comply with export compliance / encryption questions (typical HTTPS-only apps answer the standard “uses encryption / exempt” flow)

### Store listing (minimum)

- App name, subtitle, description
- Keywords
- Support URL (and marketing URL if you have one)
- **Privacy Policy URL:** `https://sharelist.servehttp.com/privacy`
- Screenshots for required device sizes (6.7" / 6.5" / etc. as Console prompts)
- App icon 1024×1024 (no alpha)
- Age rating questionnaire
- **App Privacy** nutrition labels (account, location, usage data — match what you declare in Play / privacy policy)

### Review notes (helpful)

Mention:

- Host starts a session; connectors join via QR / 6-character code / `sharelist://` link
- Music plays through the **official YouTube IFrame** player (no stream ripping)
- Optional Google Sign-In; guest host is allowed
- Location is optional and only used for country on public charts
- Test account if Google OAuth consent is still in Testing mode

---

## 6. Permissions & App Review expectations

Apple reviews usage strings and runtime prompts. Copy is already in `Info.plist`. Still:

- Request **camera** when opening the QR scanner, not only at cold start if you can avoid surprise prompts.
- Request **location** when starting host (country for charts); denial → `unknown` is fine.
- Background **audio** is justified for host playback; do not abuse other background modes.
- Do not scrape YouTube audio; keep IFrame / Data API usage consistent with [`docs/play_reviewer_youtube.md`](play_reviewer_youtube.md) if present.

---

## 7. Deep links & associated domains (optional later)

**Today:** custom scheme `sharelist://` is enough for “Open in app” from the join bridge.

**Later (Universal Links):** add an Associated Domains capability and host an `apple-app-site-association` file on `sharelist.servehttp.com` so `https://sharelist.servehttp.com/join/…` opens the app without the bridge page. Not required for first ship.

---

## 8. Checklist before first submit

- [ ] Apple Developer Program active; bundle ID `com.sharelist.shareList` registered
- [ ] Xcode signing (team + distribution) works; Archive succeeds
- [ ] Google iOS OAuth client + reversed client ID URL scheme in `Info.plist` (keep `sharelist` scheme)
- [ ] Version/build bumped in `pubspec.yaml`
- [ ] Privacy Policy URL set in App Store Connect
- [ ] App Privacy labels filled
- [ ] Screenshots + 1024 icon uploaded
- [ ] TestFlight install works on a physical device (host + connect + Google + guest)
- [ ] Relay reachable over **WSS/HTTPS** on cellular (no cleartext dependency for production)

---

## 9. Common problems

| Problem | Fix |
|---------|-----|
| `No valid code signing certificates` | Add Apple ID in Xcode Accounts; enable automatic signing or create certs in Developer portal |
| Pod / plugin build errors | `cd ios && pod repo update && pod install`; Xcode version too old → update |
| Google Sign-In returns immediately / fails | Missing reversed client ID scheme or wrong bundle ID on OAuth client |
| Deep link does nothing | Confirm `sharelist` URL scheme still in `Info.plist`; reinstall app after plist change |
| Archive greyed out | Select a real **Any iOS Device** / generic iOS device destination, not a simulator |
| App Store reject: missing purpose string | Ensure all used APIs have matching `NS*UsageDescription` keys |

---

## 10. Quick command reference

```bash
cd apps/mobile

flutter pub get
cd ios && pod install && cd ..

flutter devices
flutter run -d <device>

flutter build ios --release
flutter build ipa
```

Open workspace:

```bash
open ios/Runner.xcworkspace
```

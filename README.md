# StoopSave — iOS app

The iOS twin of the StoopSave Android app (`com.stoopsave.app`). A thin
`WKWebView` shell around the same web app — **https://stoopsave.com/app** —
with the same `window.StoopSaveApp` native bridge contract, so the web
frontend needs zero changes.

## What's in here

| File | What it does |
|---|---|
| `App/Sources/AppDelegate.swift` | OneSignal init (same app ID as Android), push-tap deep links, Universal Links, `stoopsave://auth` OAuth deep link |
| `App/Sources/SaveViewController.swift` | WKWebView host, `prompt()` bridge interception, bridge-state re-push on page load |
| `App/Sources/BridgeDispatcher.swift` | Routes `stoopsave://app/<method>` calls; camera/location permission helpers (same settled-first pattern as Android) |
| `App/Sources/ScanBridge.swift` | `scanDocument()` via VisionKit document camera; result delivered as `window.onNativeScanResult(dataUrl)` exactly like Android |
| `App/Sources/PushBridge.swift` | OneSignal player-ID cache + observer (keeps `getOneSignalPlayerId()` synchronous) |
| `App/Resources/bridge.js` | Injected at document start; defines `window.StoopSaveApp` with all 12 Android methods, synchronous via `prompt()` interception |
| `App/Resources/Info.plist` | Bundle `com.stoopsave.app`, camera/location/photo usage strings, `stoopsave://` URL scheme, navy launch screen |
| `App/Resources/StoopSave.entitlements` | Universal Links (`applinks:stoopsave.com`) + push capability |

### Bridge parity with Android (12/12)

`getFcmToken`, `getFcmDebug`, `performHaptic`, `getOneSignalPlayerId`,
`getPendingOAuthSession`, `getVersion`, `ensureCameraPermission`,
`cameraState`, `ensureLocationPermission`, `locationState`, `shareOffer`,
`scanDocument` — all present with identical signatures and semantics.
`getFcmToken()` returns `""` (iOS has no FCM; the page already falls back to
the OneSignal player ID).

### Scanner note

Android uses Google's ML Kit document scanner. iOS uses Apple's VisionKit
`VNDocumentCameraViewController` — same auto edge-detect + perspective
correction UX, zero extra dependencies, guaranteed to compile. Swapping to
ML Kit's iOS `DocumentScanner` module later only touches `ScanBridge.scan()`;
the bridge contract is unchanged.

## Cloud builds (no Mac needed)

Pushing to the `main` branch of the GitHub repo (or running the workflow
manually) triggers **ios-build-unsigned** on a macOS runner:

1. `brew install xcodegen` → `xcodegen generate`
2. Resolve Swift packages (OneSignal 5.x)
3. `xcodebuild … CODE_SIGNING_ALLOWED=NO` — unsigned release build
4. Packages `StoopSave-unsigned.ipa`, uploads it as a build artifact

This proves the Swift compiles and the bundle assembles. The IPA is
**unsigned** — it cannot install on a phone yet.

### First-time setup

1. Create a GitHub repo (e.g. `stoopsave-ios`), push this directory as its root.
2. The workflow runs automatically on the first push.

## What only you can do (needs the Apple Developer account, $99/yr)

- [ ] **Enroll** at developer.apple.com → you get a Team ID.
- [ ] **Register** bundle ID `com.stoopsave.app`.
- [ ] **APNs key**: create a `.p8` key in the developer portal, upload it in
      the OneSignal dashboard under the existing StoopSave app → Settings →
      Platforms → Apple iOS. (Without this, iOS devices can't receive pushes.)
- [ ] **Universal Links**: replace `<TEAM_ID>` in
      `docs/apple-app-site-association.json` with your Team ID, then serve the
      file at `https://stoopsave.com/.well-known/apple-app-site-association`
      (no extension, content-type `application/json`) — the iOS twin of the
      Android `assetlinks.json` that's already live.
- [ ] **Sign the build**: add signing to the workflow (provisioning profile +
      certificate) or build in Xcode → TestFlight.
- [ ] Optional later: OneSignal **Notification Service Extension** (rich push
      images, badge counts) — needs an app extension target.

## Versioning

iOS starts at **1.0 (build 1)** — it's a new App Store app. Kept independent
of the Android version code.

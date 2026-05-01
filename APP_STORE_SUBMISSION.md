# Momento App Store Submission Notes

Momento is an iOS-only, local-first private scrapbook for 3D scans of physical collectibles. This document captures the submission checks that are easy to miss after the app already builds.

## Current Review Posture

- Minimum OS: iOS 18.0.
- Distribution scope: iPhone and iPad only. Mac Catalyst and Designed for iPhone/iPad on Mac are disabled by project setting; also leave Mac availability unchecked in App Store Connect unless the product decision changes.
- Platform: iPhone/iPad via SwiftUI, SwiftData, RealityKit Object Capture, PhotogrammetrySession, Quick Look, AVFoundation, LocalAuthentication.
- Privacy posture: private by default, local-first storage, Face ID lock optional, no public sharing defaults.
- Asset strategy: USDZ, images, and audio are stored as files in Application Support. SwiftData stores metadata and relative paths only.
- Model quality: no compression step is applied to reconstructed USDZ output by product choice.

## App Review Notes Draft

Momento uses Apple Object Capture to create private 3D USDZ models of collectibles. Scanning requires a supported device and enough lighting/space. All core collection data is stored locally on device. Optional cloud object suggestions are off by default, require explicit user opt-in, and require an HTTPS endpoint. The app does not publish or publicly share user content by default.

Suggested reviewer flow:

1. Launch Momento and complete onboarding.
2. Use sample/manual item creation if Object Capture hardware is unavailable.
3. Open an item detail page, add metadata, photos, notes, and a voice memo.
4. Use the 3D preview or AR Quick Look for a USDZ-backed item.
5. Export an insurance report from Settings.

## Privacy Nutrition Draft

Confirm these answers in App Store Connect before submission:

- Data collected by developer: none, unless you later provide a first-party cloud suggestion endpoint.
- Data used for tracking: no.
- Precise location: no. Imported/exported images are sanitized where possible to avoid GPS EXIF leakage.
- User content: stored locally on device; not transmitted by default.
- Diagnostics: no third-party analytics SDK is currently present.

## Export Compliance Draft

Momento uses Apple platform security APIs and HTTPS transport only for optional user-configured cloud suggestions. It does not implement custom encryption. In App Store Connect, the likely answer is that the app does not use non-exempt encryption. Confirm with counsel or Apple guidance before final submission.

## Rejection Risk Register

| Risk | Mitigation |
| --- | --- |
| Object Capture cannot be exercised on reviewer hardware | Include review notes explaining supported hardware and provide a non-scan path for browsing/sample/manual item data. |
| Camera, microphone, or photo usage strings are unclear | Keep purpose strings specific to scan capture, voice memos, and scrapbook photo import. |
| Optional cloud suggestions imply unexpected upload | Keep it off by default, require HTTPS, show consent copy, and document it in privacy notes. |
| App locks user out after enabling Face ID | Face ID is gated by successful local/device authentication before enabling. |
| Export leaks location metadata | Export service creates sanitized photo copies before sharing data archives. |
| Large files affect device storage | App warns for low disk space and provides cleanup/orphan handling. |
| TestFlight archive fails signing | Verify bundle ID, team, provisioning, entitlements, and archive with a real Apple developer account. |

Local command-line archives may be signed with an Apple Development profile. For TestFlight/App Store submission, distribute from Xcode Organizer with App Store Connect distribution signing so `get-task-allow` is false in the final submitted build.

## Physical Device Install Checklist

1. Connect the iPhone by USB, unlock it, and keep it on the Home Screen.
2. Trust the Mac if prompted.
3. Confirm Developer Mode is enabled and restart the phone after enabling it.
4. Open Xcode Devices and Simulators and wait for the device to finish preparation.
5. Select the physical iPhone as the run destination.
6. Use Product > Run for install. Product > Build only compiles and does not install an app.

If `xcrun devicectl list devices` shows the phone as unavailable/offline, Xcode cannot install even when generic builds succeed.

## Local Release Smoke Test

Run:

```sh
./scripts/release_smoke_test.sh
```

The script writes logs to `build/release-smoke/` and creates a local archive at `/tmp/MomentoRelease.xcarchive`.
It also writes `.xcresult` bundles to `build/release-smoke/xcresults/`.

To inspect a result bundle after a failing test/build:

```sh
./scripts/inspect_xcresult.sh build/release-smoke/xcresults/tests.xcresult
```

## Device Diagnostics

Run:

```sh
./scripts/device_diagnostics.sh
```

To include details for a specific CoreDevice identifier:

```sh
./scripts/device_diagnostics.sh 34103A8E-3AC2-528F-B2ED-C0960AE7F55A
```

The script writes logs to `build/device-diagnostics/`.

## App Store Export Helper

After creating an archive and after distribution signing is available, run:

```sh
./scripts/export_appstore_archive.sh /tmp/MomentoRelease.xcarchive /tmp/MomentoAppStoreExport
```

The export helper uses `Config/AppStoreExportOptions.plist`. If Apple changes accepted export-option values in a future Xcode, update the `method` value there and rerun the script.

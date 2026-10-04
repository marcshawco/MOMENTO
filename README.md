# Momento

Momento is an iOS 26+ SwiftUI app for collectors who want private 3D digital twins of physical collectibles. It uses RealityKit Object Capture and on-device photogrammetry to create USDZ models, then stores each item in a local-first scrapbook archive with photos, notes, tags, purchase details, insurance values, serial numbers, provenance notes, and voice memos.

## Core Features

- Guided 3D capture with `ObjectCaptureSession` and `ObjectCaptureView`
- Photo Set Reconstruction from required front, back, left, right, top, and bottom photos plus optional detail shots
- On-device USDZ reconstruction with `PhotogrammetrySession`
- Local-first SwiftData metadata storage
- File-backed storage for USDZ models, thumbnails, photos, and audio
- In-app 3D preview plus AR Quick Look
- Photo import/export sanitization to avoid GPS EXIF leakage
- Optional Face ID app lock
- PDF, CSV, and JSON-plus-assets exports
- On-device object metadata suggestions with optional HTTPS-only cloud endpoint

## Requirements

- Xcode 26 or newer (the iOS 26 SDK is required to build the deployment target)
- iOS 26.0+
- Swift 5 language mode, Swift 6 toolchain
- A LiDAR-capable iPhone or iPad for real Object Capture flows

The simulator can build, run, and test the non-capture paths. Object Capture itself requires supported physical hardware.

## Supported Devices

Momento's deployment target is iOS 26.0, so the app installs on any iPhone or iPad that can
run iOS/iPadOS 26. Capture is gated separately, because the two capture paths have different
hardware requirements:

| Capability | Requirement | Runtime check |
| --- | --- | --- |
| Shelf, metadata, photos, notes, voice memos, exports, AR Quick Look | Any iOS 26 device | none |
| Photo Set Reconstruction | On-device photogrammetry support | `PhotogrammetrySession.isSupported` |
| Guided LiDAR Scan | LiDAR Scanner plus a supported SoC | `ObjectCaptureSession.isSupported` |

`MOMENTO/Utilities/DeviceCapability.swift` centralizes these checks. The runtime checks are
authoritative; treat the model names below as guidance for QA device selection rather than as a
gate in code, and re-check them against Apple's current device compatibility list before release.

Recommended for guided LiDAR capture:

- iPhone 17 Pro / 17 Pro Max, iPhone 16 Pro / 16 Pro Max, iPhone 15 Pro / 15 Pro Max (recommended baseline)
- iPhone 14 Pro / 14 Pro Max, iPhone 13 Pro / 13 Pro Max, iPhone 12 Pro / 12 Pro Max (supported, slower reconstruction)
- iPad Pro 11-inch and 13-inch (M4/M5), iPad Pro 11-inch (2nd generation, 2020) and later, iPad Pro 12.9-inch (4th generation, 2020) and later

Non-LiDAR iPhone and iPad models that run iOS 26 fall back to Photo Set Reconstruction when
`PhotogrammetrySession.isSupported` is true. The Add Item screen disables and explains any
capture mode the current device cannot run, so an unsupported device never reaches the camera.

Reconstruction is GPU- and thermal-heavy. Prefer a Pro-class device with free storage above the
500 MB floor in `AppConstants.Limits.minimumDiskSpaceMB` for QA on large capture sets.

## Project Structure

- `MOMENTO/Models`: SwiftData models and value transformers
- `MOMENTO/Utilities`: app constants and `DeviceCapability` hardware gating
- `MOMENTO/Services`: file storage, export, capture quality, photo import, permissions, authentication, and metadata suggestion services
- `MOMENTO/ViewModels`: capture flow and item detail logic
- `MOMENTO/Views`: SwiftUI screens for onboarding, shelf, capture, item detail, settings, and shared components
- `MOMENTOTests`: unit tests for critical privacy, storage, export, and capture guidance logic
- `RELEASE_CHECKLIST.md`: release gates for automated checks, physical-device QA, privacy/security review, and App Store Connect
- `APP_STORE_METADATA_DRAFT.md`: App Store listing copy, review notes, permission explanations, and privacy-answer draft

## Build And Test

Run unit tests:

```sh
xcodebuild test -project MOMENTO.xcodeproj -scheme MOMENTO -destination "$(./scripts/resolve_test_destination.sh)"
```

`resolve_test_destination.sh` picks the newest installed simulator running iOS 26 or later and
fails loudly if none exists. Pass `DEVICE_FAMILY=ipad` for an iPad destination:

```sh
xcodebuild test -project MOMENTO.xcodeproj -scheme MOMENTO -destination "$(DEVICE_FAMILY=ipad ./scripts/resolve_test_destination.sh)"
```

Run a generic iOS build:

```sh
xcodebuild -project MOMENTO.xcodeproj -scheme MOMENTO -destination 'generic/platform=iOS' build
```

Run a Release generic iOS build:

```sh
xcodebuild -project MOMENTO.xcodeproj -scheme MOMENTO -configuration Release -destination 'generic/platform=iOS' build
```

Create a local archive:

```sh
xcodebuild archive -project MOMENTO.xcodeproj -scheme MOMENTO -configuration Release -destination 'generic/platform=iOS' -archivePath /tmp/MomentoRelease.xcarchive
```

Inspect archive/app/export metadata before distribution:

```sh
./scripts/verify_archive_metadata.sh /tmp/MomentoRelease.xcarchive
```

Validate App Store Connect metadata draft lengths:

```sh
./scripts/validate_app_store_metadata.sh
```

Run the full local release smoke test:

```sh
./scripts/release_smoke_test.sh
```

The smoke script runs the test suite on both an iPhone and an iPad simulator, auto-selecting
iOS 26+ destinations. Override or skip them when needed:

```sh
TEST_DESTINATION='platform=iOS Simulator,name=iPhone 17 Pro,OS=26.3' ./scripts/release_smoke_test.sh
```

```sh
RUN_IPAD_TESTS=0 ./scripts/release_smoke_test.sh
```

Run the full release preflight:

```sh
./scripts/preflight_release.sh
```

Inspect a smoke-test result bundle after a failure:

```sh
./scripts/inspect_xcresult.sh build/release-smoke/xcresults/tests.xcresult
```

Capture the current booted Simulator screen for App Store screenshots:

```sh
./scripts/capture_app_store_screenshot.sh onboarding-privacy
```

Export an archive for App Store/TestFlight distribution after you have distribution signing available:

```sh
./scripts/export_appstore_archive.sh /tmp/MomentoRelease.xcarchive /tmp/MomentoAppStoreExport
```

For a distribution-signed export, verify stricter signing requirements:

```sh
EXPECT_DISTRIBUTION=1 ./scripts/verify_archive_metadata.sh /tmp/MomentoAppStoreExport
```

## Run On A Physical iPhone

Use Product > Run in Xcode, not Product > Build. A successful build by itself only produces build artifacts; it does not install or launch the app unless a runnable device destination is selected.

Or use the command-line install helper:

```sh
DEVICE_ID=00008140-001C29A93E12801C ./scripts/install_on_device.sh
```

The helper builds into `/tmp/MomentoDeviceDerivedData` instead of the project `build/` folder. This avoids physical-device codesign failures caused by extended attributes that can appear in FileProvider or iCloud-synced project directories.

Before running on device:

- Connect the iPhone by USB for the first run.
- Unlock the iPhone and keep it on the Home Screen.
- Accept any "Trust This Computer" prompt on the iPhone.
- Confirm Developer Mode is enabled on the iPhone.
- In Xcode, select the physical iPhone as the active run destination.
- Wait for Xcode's Devices and Simulators window to finish preparing the device.

Useful diagnostics:

```sh
xcodebuild -project MOMENTO.xcodeproj -scheme MOMENTO -showdestinations
xcrun devicectl list devices
xcrun xctrace list devices
```

Or capture all diagnostics to logs:

```sh
./scripts/device_diagnostics.sh
```

To include detailed CoreDevice output for a known device identifier:

```sh
./scripts/device_diagnostics.sh 34103A8E-3AC2-528F-B2ED-C0960AE7F55A
```

If the phone appears as unavailable or offline, Xcode can build for "Any iOS Device" but cannot install Momento. In that state, unplug and reconnect by USB, unlock the phone, reopen Xcode's Devices and Simulators window, and wait until the iPhone appears as an available destination before using Product > Run.

## Privacy Model

Momento is private by default:

- Metadata is stored locally with SwiftData.
- Large files are stored in app-managed directories, not in SwiftData blobs.
- Public sharing is not enabled by default.
- Imported and exported photos are sanitized when possible.
- Cloud suggestions are optional, off by default, and require HTTPS.
- Face ID requires successful device authentication before it can be enabled.

## Object Capture Notes

Momento preserves detailed USDZ output and does not compress reconstructed model files. The app
requests RealityKit photogrammetry detail as `.reduced`. As of the iOS 26 SDK, `.reduced` is still
the only `PhotogrammetrySession.Request.Detail` case available on iOS — `.preview`, `.medium`,
`.full`, and `.raw` are macOS-only and do not compile for an iOS target. If Apple expands supported
detail levels, update both capture requests and verify on physical hardware before release.

Apple's guided `ObjectCaptureSession` flow is optimized for a stationary object on a stable, textured surface while the camera moves around it. For small collectibles that are hard to place, Momento exposes a Handheld Scan fallback: keep the object centered, rotate it slowly, avoid covering important detail with fingers, and capture many sharp angles against a textured background. Pure "rotate it in your hand" capture support is uncertain in Apple's guided API; Momento's safe fallback is to collect manual images and send that image set through `PhotogrammetrySession`.

Photo Set Reconstruction is the preferred fallback when guided capture stalls. The user supplies front, back, left, right, top, and bottom photos, then can add optional diagonal, edge, label, texture, and close-up shots. Six canonical views are enough to attempt reconstruction, but dense overlap still matters; local AI should be used for future quality scoring, background masking, and missing-angle prompts rather than promising perfect 3D from six unrelated photos.

## Release Status

The repository builds, tests, and archives locally. Before TestFlight or App Store submission, complete the physical-device gates in `RELEASE_CHECKLIST.md`, especially real LiDAR capture, AR Quick Look verification, Face ID failure recovery, and export privacy inspection.

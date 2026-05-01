# Momento

Momento is an iOS 18+ SwiftUI app for collectors who want private 3D digital twins of physical collectibles. It uses RealityKit Object Capture and on-device photogrammetry to create USDZ models, then stores each item in a local-first scrapbook archive with photos, notes, tags, purchase details, insurance values, serial numbers, provenance notes, and voice memos.

## Core Features

- Guided 3D capture with `ObjectCaptureSession` and `ObjectCaptureView`
- On-device USDZ reconstruction with `PhotogrammetrySession`
- Local-first SwiftData metadata storage
- File-backed storage for USDZ models, thumbnails, photos, and audio
- In-app 3D preview plus AR Quick Look
- Photo import/export sanitization to avoid GPS EXIF leakage
- Optional Face ID app lock
- PDF, CSV, and JSON-plus-assets exports
- On-device object metadata suggestions with optional HTTPS-only cloud endpoint

## Requirements

- Xcode 16 or newer
- iOS 18.0+
- Swift 5.9+
- A LiDAR-capable iPhone or iPad for real Object Capture flows

The simulator can build, run, and test the non-capture paths. Object Capture itself requires supported physical hardware.

## Project Structure

- `MOMENTO/Models`: SwiftData models and value transformers
- `MOMENTO/Services`: file storage, export, capture quality, photo import, permissions, authentication, and metadata suggestion services
- `MOMENTO/ViewModels`: capture flow and item detail logic
- `MOMENTO/Views`: SwiftUI screens for onboarding, shelf, capture, item detail, settings, and shared components
- `MOMENTOTests`: unit tests for critical privacy, storage, export, and capture guidance logic
- `RELEASE_CHECKLIST.md`: release gates for automated checks, physical-device QA, privacy/security review, and App Store Connect

## Build And Test

Run unit tests:

```sh
xcodebuild test -project MOMENTO.xcodeproj -scheme MOMENTO -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
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

## Privacy Model

Momento is private by default:

- Metadata is stored locally with SwiftData.
- Large files are stored in app-managed directories, not in SwiftData blobs.
- Public sharing is not enabled by default.
- Imported and exported photos are sanitized when possible.
- Cloud suggestions are optional, off by default, and require HTTPS.
- Face ID requires successful device authentication before it can be enabled.

## Object Capture Notes

Momento preserves detailed USDZ output and does not compress reconstructed model files. The app currently requests RealityKit photogrammetry detail as `.reduced` because that is the supported on-device Object Capture detail level for this iOS path. If Apple expands supported detail levels, update the capture request and verify on physical hardware before release.

## Release Status

The repository builds, tests, and archives locally. Before TestFlight or App Store submission, complete the physical-device gates in `RELEASE_CHECKLIST.md`, especially real LiDAR capture, AR Quick Look verification, Face ID failure recovery, and export privacy inspection.

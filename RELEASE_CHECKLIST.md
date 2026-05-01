# Momento Release Checklist

Momento is an iOS 18+ SwiftUI app for private, local-first collectible archiving with RealityKit Object Capture, on-device photogrammetry, SwiftData metadata, file-backed assets, in-app model preview, and AR Quick Look.

## Automated Gates

- Run unit tests:
  `xcodebuild test -project MOMENTO.xcodeproj -scheme MOMENTO -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`
- Run generic iOS build:
  `xcodebuild -project MOMENTO.xcodeproj -scheme MOMENTO -destination 'generic/platform=iOS' build`
- Run Release generic iOS build:
  `xcodebuild -project MOMENTO.xcodeproj -scheme MOMENTO -configuration Release -destination 'generic/platform=iOS' build`
- Create a local archive:
  `xcodebuild archive -project MOMENTO.xcodeproj -scheme MOMENTO -configuration Release -destination 'generic/platform=iOS' -archivePath /tmp/MomentoRelease.xcarchive`
- Or run the full local smoke pass:
  `./scripts/release_smoke_test.sh`
- Inspect a failed test/build result bundle:
  `./scripts/inspect_xcresult.sh build/release-smoke/xcresults/tests.xcresult`
- Inspect archive/app/export Info.plist, privacy manifest, platform, and signing:
  `./scripts/verify_archive_metadata.sh /tmp/MomentoRelease.xcarchive`
- Validate App Store Connect metadata draft lengths:
  `./scripts/validate_app_store_metadata.sh`
- Capture physical device/Xcode diagnostics:
  `./scripts/device_diagnostics.sh`
- Export an existing archive for App Store Connect/TestFlight:
  `./scripts/export_appstore_archive.sh /tmp/MomentoRelease.xcarchive /tmp/MomentoAppStoreExport`

## Required Real-Device QA

- Install on an iOS 18+ LiDAR-capable iPhone or iPad.
- Complete onboarding without enabling Face ID.
- Complete onboarding with Face ID enabled, including cancel/failure recovery.
- Capture at least three collectibles with different materials:
  - matte object
  - glossy or reflective object
  - small detailed object
- Confirm weak capture sets are rejected before reconstruction.
- Confirm successful scans produce USDZ files and thumbnails.
- Open each item detail page and verify model preview loads.
- Open each model in AR Quick Look.
- Add and delete photo, text, and voice memo attachments.
- Delete an item and confirm the UI no longer references removed assets.
- Export PDF, CSV, and data archive; inspect files for expected metadata and sanitized photos.

## Privacy And Security Gates

- Confirm no public sharing is enabled by default.
- Confirm imported and exported photos do not include GPS EXIF metadata.
- Confirm Face ID cannot be enabled without successful device authentication.
- Confirm cloud suggestions remain disabled by default.
- Confirm cloud suggestions reject non-HTTPS endpoints.
- Confirm app storage paths cannot escape Momento-managed asset directories.
- Confirm `PrivacyInfo.xcprivacy` is included in the app bundle.

## App Store Connect Gates

- Archive with App Store distribution signing, not development signing.
- Confirm `SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD = NO` unless the product decision changes.
- Upload through Xcode Organizer or Transporter.
- If using command-line export, use `Config/AppStoreExportOptions.plist` and verify the exported app is distribution-signed with `get-task-allow` false.
- For distribution-signed artifacts, run:
  `EXPECT_DISTRIBUTION=1 ./scripts/verify_archive_metadata.sh /tmp/MomentoAppStoreExport`
- Complete privacy nutrition labels consistently with `PrivacyInfo.xcprivacy`.
- Validate listing copy before pasting into App Store Connect:
  `./scripts/validate_app_store_metadata.sh`
- Answer export compliance as no non-exempt encryption.
- Add screenshots for onboarding, shelf, item detail, 3D preview, and export.
- Verify TestFlight build on at least one physical LiDAR device before external testing.

## Current Known Limitations

- Object Capture and reconstruction require supported physical hardware; simulator shows an unsupported-device message.
- iCloud sync, StoreKit subscription gating, and full provenance manifest export are intentionally deferred.
- iOS Object Capture photogrammetry detail is explicitly requested as `.reduced` because this is the currently supported on-device RealityKit detail level; preserve original USDZ output and do not add model compression.

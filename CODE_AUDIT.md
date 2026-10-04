# Momento Code Audit

Date: 2026-10-04
Commit audited: `e8fcdf3` plus the iOS 26 migration in this change
Scope: all 8,500 lines of Swift in `MOMENTO/` and `MOMENTOTests/`, the Xcode project, the
release scripts, and the CI workflow.

Every finding below was read in the source, not inferred. Line numbers are from the tree after
the iOS 26 migration landed. Two findings (H1, H2) were fixed as part of this change; the rest
are reported only.

## Summary

| Severity | Count | Theme |
| --- | --- | --- |
| High | 4 | one broken feature, one data race, one privacy gap, one missing migration plan |
| Medium | 19 | main-thread blocking, memory pressure, i18n, export fidelity, dead code |
| Low | 9 | polish, consistency, unused constants |

The codebase is in good shape overall. It is consistently structured, the file-storage path
containment is properly implemented *and* tested, error states are modelled rather than
swallowed, and the privacy posture is real rather than cosmetic. The weak spots cluster in three
places: concurrency isolation on the non-`@MainActor` services, main-thread work in the export
and image paths, and the gap between what "sanitized" is advertised to mean and what it does.

---

## High

### H1. Voice memo playback state never reached the UI — FIXED

`AudioRecordingService.play()` began with `stopPlayback()`, which sets
`currentlyPlayingFileName = nil`. The caller in `VoiceMemosTabView` set that field *before*
calling `play()`, so the reset wiped it immediately. `isPlaying(_:)` compares against it, so it
always returned `false`: the row kept showing a play icon instead of stop, and the playback
progress bar never appeared, even though audio was playing.

Fixed by giving `play(url:fileName:)` ownership of the field and setting it after the reset.

- [MOMENTO/Services/AudioRecordingService.swift:84](MOMENTO/Services/AudioRecordingService.swift:84)
- [MOMENTO/Views/ItemDetail/VoiceMemosTabView.swift:148](MOMENTO/Views/ItemDetail/VoiceMemosTabView.swift:148)

### H2. `AudioRecordingService` was not actually MainActor-isolated — FIXED

The doc comment read "MainActor-isolated (default)", but the class had no `@MainActor`. A plain
`@Observable final class` is nonisolated in Swift 5 language mode, so the recording and playback
timer `Task`s were mutating observable state and reading `AVAudioRecorder.currentTime` /
`AVAudioPlayer.currentTime` off the main actor. `AVAudioPlayer` and `AVAudioRecorder` are not
thread-safe, and `@Observable` mutations from a background thread can corrupt SwiftUI's
dependency tracking.

This is also a hard error under Swift 6 language mode, so it blocked that migration.

Fixed by adding `@MainActor` and correcting the comment. Compare `AuthenticationService` and
`PermissionService`, which declare it explicitly.

- [MOMENTO/Services/AudioRecordingService.swift:6](MOMENTO/Services/AudioRecordingService.swift:6)

### H3. "Sanitized" photos keep most identifying metadata

`sanitizedImageData(from:)` removes exactly one dictionary, `kCGImagePropertyGPSDictionary`, and
copies every other source property straight through to the output. That leaves EXIF
(`DateTimeOriginal`, lens, serial), TIFF (`Make`, `Model`, `Software`), the Apple maker-note
dictionary, IPTC (which can carry location *names* and creator contact info), and XMP intact.

The README, the App Store draft, and the onboarding copy all describe this as sanitization that
protects privacy. For GPS coordinates specifically that is true. For "this photo cannot be traced
back to me or my home" it is not, and this app's entire pitch is privacy. The test
(`testSanitizedImageDataRemovesGPSMetadata`) only asserts GPS removal, so the gap is invisible to
CI.

Suggested fix: strip to an allowlist (orientation, colour profile, pixel dimensions) rather than
denying one key, and extend the test to assert that EXIF/TIFF/IPTC/maker-note dictionaries are
absent.

- [MOMENTO/Services/PhotoImportService.swift:63](MOMENTO/Services/PhotoImportService.swift:63)

### H4. No SwiftData schema migration plan

The app builds its container from a bare `Schema([...])` with no `VersionedSchema` and no
`SchemaMigrationPlan` anywhere in the tree. It relies entirely on SwiftData's lightweight
automatic migration. That works for additive changes and silently fails — or refuses to open the
store — for anything else.

`AppConstants.Persistence.schemaVersion` exists but is never read, so there is no version marker
in the store either. The startup path does handle container failure gracefully
(`StartupResult.failed`), which is good, but "Momento could not open its private database" is a
total data-loss event for a local-first app with no cloud backup.

This should be closed before the first App Store release, because the first shipped schema is the
one you are stuck migrating from.

- [MOMENTO/MOMENTOApp.swift:17](MOMENTO/MOMENTOApp.swift:17)
- [MOMENTO/Utilities/Constants.swift:6](MOMENTO/Utilities/Constants.swift:6)

---

## Medium

### M1. App only locks on `.background`, not `.inactive`

`onChange(of: scenePhase)` calls `authService.lock()` only for `.background`. iOS takes the
app-switcher snapshot during `.inactive`, so the unlocked collection is captured into the
multitasking card and visible to anyone who swipes up. Standard hardening is to lock or blur on
`.inactive`.

- [MOMENTO/MOMENTOApp.swift:50](MOMENTO/MOMENTOApp.swift:50)

### M2. The lock overlay probably does not cover `fullScreenCover` content

`LockScreenView` is attached with `.overlay {}` on `ShelfView`. The capture flow, photo-set flow,
and AR preview are presented with `.fullScreenCover` *from* that same view, which puts them in a
presentation layer above the overlay. If the app is backgrounded and resumed while one of those
is open, the lock is likely to be underneath the cover and the content visible.

Worth verifying on device before release. A more robust pattern is to gate the scene's root
content on `isUnlocked` rather than overlay it.

- [MOMENTO/MOMENTOApp.swift:42](MOMENTO/MOMENTOApp.swift:42)

### M3. `ItemDetailView` loads the entire collection to find one item

`@Query private var items: [CollectionItem]` has no predicate, then `items.first { $0.id == itemId }`
scans it. Opening any item detail screen fetches and materializes every item in the store along
with its relationships. Should be a `FetchDescriptor` with a `#Predicate` on `id`, or pass the
`PersistentIdentifier` and use `modelContext.model(for:)`.

- [MOMENTO/Views/ItemDetail/ItemDetailView.swift:13](MOMENTO/Views/ItemDetail/ItemDetailView.swift:13)

### M4. All exports run on the main actor

`exportPDF`, `exportCSV`, and `exportDataArchive` wrap the work in `Task {}` inside a
MainActor-isolated view, so the task inherits the main actor. `generateDataArchive` reads every
asset into memory and computes SHA-256 over all of them — including multi-megabyte USDZ models —
and `generatePDFReport` decodes thumbnails and up to three photos per item synchronously. For a
large collection this is a multi-second main-thread freeze, during which the
`ExportProgressView` spinner cannot even animate.

`ExportService` is already `nonisolated ... Sendable`, so moving this to `Task.detached` is
mostly a matter of changing the call sites.

- [MOMENTO/Views/Settings/SettingsView.swift:184](MOMENTO/Views/Settings/SettingsView.swift:184)
- [MOMENTO/ViewModels/ItemDetailViewModel.swift:268](MOMENTO/ViewModels/ItemDetailViewModel.swift:268)

### M5. Export manifest can crash on duplicate file names

`makeDataArchiveManifest` builds two dictionaries with `Dictionary(uniqueKeysWithValues:)` keyed
on asset file name. Duplicate keys are a runtime trap, not an error — the app crashes. File names
are UUIDs so a collision is improbable, but a crash is a harsh failure mode for an export path,
and the photo-set reconstruction path does write deterministic names. Use
`Dictionary(_:uniquingKeysWith:)`.

- [MOMENTO/Services/ExportService.swift:174](MOMENTO/Services/ExportService.swift:174)

### M6. CSV export is open to formula injection

`escapeCSV` correctly quotes fields containing `,`, `"`, or newlines, but does not neutralize a
leading `=`, `+`, `-`, or `@`. An item titled `=HYPERLINK("http://...","click")` becomes a live
formula when the CSV is opened in Excel or Numbers. These reports are explicitly meant to be sent
to insurers, so the file does leave the user's control. Prefix at-risk fields with a `'` or a tab.

- [MOMENTO/Services/ExportService.swift:474](MOMENTO/Services/ExportService.swift:474)

### M7. Export file names collide within the same day

`exportFileURL` names files `Momento_Catalog_2026-10-04.csv` — date only, no time. A second export
on the same day silently overwrites the first. Worse, `SanitizedPhotos/` is never cleared between
runs, so stale sanitized copies from an earlier export are picked up and re-shared. And
`cleanupExportFiles` deletes the whole temp directory, which can pull files out from under an
open share sheet.

- [MOMENTO/Services/ExportService.swift:468](MOMENTO/Services/ExportService.swift:468)
- [MOMENTO/Services/ExportService.swift:554](MOMENTO/Services/ExportService.swift:554)

### M8. The insurance PDF silently truncates data

`drawItemPage` draws into fixed-height rects — description capped at 80pt, provenance at 60pt —
and `break`s out of loops when it runs out of page, with no continuation page. Notes are capped at
the first three and photos at the first three. A long provenance note, the field most likely to
matter to an insurer, is cut off with no indication. There is no multi-page flow for a single
item.

- [MOMENTO/Services/ExportService.swift:314](MOMENTO/Services/ExportService.swift:314)

### M9. Photo-set reconstruction holds every selected image in memory

`requiredImageData: [PhotoSetViewpoint: Data]` and `optionalImageData: [Data]` keep full-resolution
image data as observable state for the lifetime of the screen. The six required views plus the
"add many optional detail photos" the UI actively encourages puts this at 50–100 MB resident
before reconstruction even starts, on top of the photogrammetry session's own footprint. That is
jetsam territory on a non-Pro device.

Write each image to the session temp directory as it is picked, and keep only thumbnails and
paths in memory.

- [MOMENTO/ViewModels/PhotoSetReconstructionViewModel.swift:67](MOMENTO/ViewModels/PhotoSetReconstructionViewModel.swift:67)

### M10. Photo-set images are written with the wrong file extension

`prepareImageSet` names every file `.jpg`, but `sanitizedImageData(from:)` preserves the *source*
container type. A HEIC pick is written as HEIC bytes in a file called `front-000.jpg`.
`PhotoImportService.importPhoto` gets this right via `inferredImageFileExtension`; this path does
not. ImageIO sniffs content so decoding still works, but `PhotogrammetrySession` input validation
and `ThumbnailService`'s extension-based filtering both key off the name.

- [MOMENTO/ViewModels/PhotoSetReconstructionViewModel.swift:229](MOMENTO/ViewModels/PhotoSetReconstructionViewModel.swift:229)

### M11. Currency is hardcoded to USD in five places

Every price is formatted with `.currency(code: "USD")`, including the two editable fields and the
PDF cover total. A user in the UK entering 400 sees "$400.00" and exports an insurance report
denominated in the wrong currency. Store a currency code on the item (or read
`Locale.current.currency`) and thread it through.

- [MOMENTO/Models/CollectionItem.swift:80](MOMENTO/Models/CollectionItem.swift:80)
- [MOMENTO/Views/ItemDetail/MetadataSection.swift:134](MOMENTO/Views/ItemDetail/MetadataSection.swift:134)
- [MOMENTO/Services/ExportService.swift:288](MOMENTO/Services/ExportService.swift:288)

### M12. No localization, despite the project being configured for it

`LOCALIZATION_PREFERS_STRING_CATALOGS = YES` and `STRING_CATALOG_GENERATE_SYMBOLS = YES` are both
set, but there is no `.xcstrings` catalog and no `.lproj` anywhere. Every string is an inline
English literal. SwiftUI will pick most of them up automatically once a catalog is added, but the
error messages built by string interpolation in `CaptureError` and `DeviceCapability` will not
localize cleanly in their current form.

### M13. `CaptureSetQualityService` reports "images look weak" when it simply could not analyze them

`evaluate` computes `usableRatio = usableImages / totalImages`. If `analyzeImage` returns `nil` for
every image — unexpected pixel format, 16-bit components, a `bitsPerPixel/8` that does not match
the real layout — `usableImages` is 0, the ratio is 0, and the user is told "Several images look
weak. Rescan with slower movement." after completing a full scan pass.

This gate sits at the end of the guided capture flow, so a format mismatch on a future device
would reject every scan with a misleading message. Distinguish "analysis unavailable"
(`analyzedImages == 0`) from "analysis says weak", and let reconstruction proceed when the
analyzer produced no samples.

- [MOMENTO/Services/CaptureSetQualityService.swift:76](MOMENTO/Services/CaptureSetQualityService.swift:76)

### M14. `analyzeImage` assumes an RGB byte layout it never checks

It reads `bytes[offset]`, `[offset+1]`, `[offset+2]` as R, G, B based only on
`bitsPerPixel / 8 >= 3`. It ignores `CGImage.bitmapInfo`, so a BGRA image silently swaps red and
blue, and a 16-bit-per-component image is read as bytes and produces meaningless luminance. The
indexing is memory-safe (`bytesPerRow >= width * bytesPerPixel` keeps it in bounds), so this is a
wrong-answer bug, not a crash. Render into a known `CGContext` format first.

- [MOMENTO/Services/CaptureSetQualityService.swift:143](MOMENTO/Services/CaptureSetQualityService.swift:143)

### M15. `ShelfView` re-filters and re-sorts the whole collection on every redraw

`filteredAndSortedItems`, `allTags`, and `allCollectionNames` are computed properties read from
the view body. Each redraw — including every keystroke in the search field — re-filters the full
array, re-sorts it, and builds two `Set`s via `flatMap`. The `@Query` already sorts by
`updatedAt`, so that work is duplicated. Search cannot move into the `@Query` predicate while
tags are stored through a value transformer (see M17).

- [MOMENTO/Views/Shelf/ShelfView.swift:241](MOMENTO/Views/Shelf/ShelfView.swift:241)

### M16. Two image paths decode at full resolution on the main thread

`ShelfItemCard` uses `AsyncImage`, which decodes the full 1024px PNG thumbnail for a 160pt cell,
in a `LazyVGrid` where many are alive at once. `PhotoFullScreenView` uses
`UIImage(contentsOfFile:)`, a synchronous full-resolution decode on the main thread as the cover
appears. The project already has `DownsampledImageView` for exactly this, and `PhotosTabView`
uses it — these two paths just do not.

- [MOMENTO/Views/Shelf/ShelfItemCard.swift:46](MOMENTO/Views/Shelf/ShelfItemCard.swift:46)
- [MOMENTO/Views/ItemDetail/PhotosTabView.swift:176](MOMENTO/Views/ItemDetail/PhotosTabView.swift:176)

### M17. The tags value transformer blocks queries and can silently erase data

`StringArrayValueTransformer` JSON-encodes `[String]` into a blob. SwiftData has supported
`[String]` natively since iOS 17, so this is legacy. Two consequences:

- Tags cannot appear in a `#Predicate`, which forces the client-side filtering in M15.
- `reverseTransformedValue` returns `[]` on any decode failure. A corrupted blob reads back as
  "no tags", and the next save writes that empty array back — silent, permanent data loss with no
  log line.

At minimum, log the decode failure. Migrating off the transformer is the real fix, but it needs
the migration plan from H4 first.

- [MOMENTO/Models/Transformers/StringArrayValueTransformer.swift:33](MOMENTO/Models/Transformers/StringArrayValueTransformer.swift:33)

### M18. Abandoned voice recordings leak into managed storage

`startRecording()` writes straight into the final `VoiceMemos/` directory, and `addVoiceMemo`
then moves that file to a *new* UUID name in the same directory. If the user records and
navigates away without stopping, or recording fails after the file is created, the original stays
behind unreferenced by SwiftData. "Clean Unreferenced Assets" in Settings recovers the space, but
the user has to know to run it. Record into `CaptureTemp/` and move on success.

- [MOMENTO/Services/AudioRecordingService.swift:38](MOMENTO/Services/AudioRecordingService.swift:38)

### M19. Cloud suggestions are not reflected in the privacy manifest

`PrivacyInfo.xcprivacy` declares `NSPrivacyCollectedDataTypes` as an empty array. When cloud
suggestions are enabled, the app POSTs a downsampled photo to a third-party endpoint. The feature
is off by default and gated behind an explicit consent alert, which is the right design — but if
it ships, the manifest and the App Store Connect privacy answers need a "Photos" entry collected
for App Functionality. This is an App Review rejection risk rather than a code bug.

- [MOMENTO/PrivacyInfo.xcprivacy](MOMENTO/PrivacyInfo.xcprivacy)

---

## Low

### L1. Debug instrumentation ships in release builds and nothing reads it

`debugEvents`, `debugFlowStateText`, `debugTrackingText`, `debugCanRequestCaptureText`, and
`debugPendingAutoStartText` are all observable state or computed properties on
`CaptureViewModel`. No view references any of them. `appendDebugEvent` is called from six places
during capture and allocates a fresh `DateFormatter` each time. Either wire it to a `#if DEBUG`
overlay or delete it.

- [MOMENTO/ViewModels/CaptureViewModel.swift:109](MOMENTO/ViewModels/CaptureViewModel.swift:109)

### L2. `CaptureViewModel` is doing too much

1,058 lines, 11 concurrent `Task` handles, three overlapping watchdog timers, plus session
observation, guidance derivation, reconstruction, thumbnailing, metadata suggestion, and SwiftData
persistence. It is the highest-risk file to change and the least tested. The guidance logic was
already extracted into `CaptureGuidanceEngine` and unit-tested — the reconstruction pipeline and
the persistence step deserve the same treatment.

### L3. Reconstruction is driven from the main actor

`reconstructionTask = Task { ... }` inside the MainActor-isolated view model inherits the main
actor, so `PhotogrammetrySession.init`, `process(requests:)`, and the `outputs` iteration all run
there. The heavy work is inside the framework, and the inline comment acknowledges this, but the
synchronous setup calls are on the main thread during a GPU-heavy operation.

- [MOMENTO/ViewModels/CaptureViewModel.swift:629](MOMENTO/ViewModels/CaptureViewModel.swift:629)

### L4. `ModelPreviewView` loads a USDZ synchronously on the main actor

`.task { loadScene() }` calls a non-async function that does `SCNScene(url:)` inline. This is the
same pattern `ThumbnailService` has a comment specifically warning about ("loading the
just-produced USDZ into a 3D renderer immediately after photogrammetry can trigger native
rendering crashes"). At minimum make the load actually asynchronous.

- [MOMENTO/Views/ItemDetail/ModelPreviewView.swift:52](MOMENTO/Views/ItemDetail/ModelPreviewView.swift:52)

### L5. Two services are not `Sendable` and will block Swift 6 language mode

`CaptureSetQualityService` and `ObjectIntelligenceService` are plain `final class` singletons with
`static let shared`, unlike their four siblings which are `nonisolated final class ... Sendable`.
Both are reachable from detached tasks.

- [MOMENTO/Services/CaptureSetQualityService.swift:54](MOMENTO/Services/CaptureSetQualityService.swift:54)
- [MOMENTO/Services/ObjectIntelligenceService.swift:15](MOMENTO/Services/ObjectIntelligenceService.swift:15)

### L6. Inconsistent relationship cleanup on delete

`deletePhoto` and `deleteVoiceMemo` both `removeAll` from the parent's array before deleting;
`deleteNote` does not. One of the two patterns is wrong — probably the `removeAll`, since the
cascade rule should handle it — and the inconsistency suggests it was added to work around a
symptom.

- [MOMENTO/ViewModels/ItemDetailViewModel.swift:208](MOMENTO/ViewModels/ItemDetailViewModel.swift:208)

### L7. `onAppear` reconfigure can discard pending edits

`ItemDetailView.onAppear` calls `viewModel.configure(item:modelContext:)`, which runs
`loadFromItem()` and overwrites the buffered fields from the store. If `onAppear` re-fires while
the 0.8s autosave debounce is still pending, in-flight typing is replaced with the stale stored
value. Guard `configure` against re-binding the same item.

- [MOMENTO/Views/ItemDetail/ItemDetailView.swift:98](MOMENTO/Views/ItemDetail/ItemDetailView.swift:98)

### L8. Small inconsistencies and dead code

- `AppConstants.Export.exportTempFolder = "Exports"` is never read; `exportTempDirectory()`
  hardcodes `"MomentoExports"`.
- `AppConstants.Persistence.schemaVersion` is never read (see H4).
- `CaptureContainerView.createTestItem()` inserts without `try modelContext.save()`, unlike every
  other persistence call site. `#if DEBUG` only.
- `AuthenticationService.isBiometricAvailable` builds a new `LAContext` on every access and is
  read from a view body, so it runs a biometric capability check per redraw.
- `AuthenticationService.authenticate()` leaves both `isUnlocked` and `authError` untouched if
  `evaluatePolicy` returns `false` without throwing, giving the user a silent dead end.
- `availableDiskSpaceMB()` returns `0` when the volume query *fails*, so an unrelated error
  surfaces as "0 MB available" and blocks capture.
- `SettingsView` calls `availableDiskSpaceMB()` from the view body — a synchronous disk stat per
  redraw.
- `FlowLayout` runs `arrange` twice per layout pass and leaves `cache` unused.
- `ItemDetailViewModel.saveToItem` writes `"Untitled"` to the store when the buffer is empty but
  leaves the buffer empty, so the UI and the store disagree.

### L9. Accessibility gaps outside the shelf

`ShelfItemCard`, the add button, the torch button, and the AR close button have labels. Most
capture controls do not. More importantly, `photoCell` and `noteCard` use `onTapGesture` on a
non-button container, so VoiceOver exposes no activation action for opening a photo or editing a
note, and the tag chips' remove buttons are unlabeled.

- [MOMENTO/Views/ItemDetail/PhotosTabView.swift:85](MOMENTO/Views/ItemDetail/PhotosTabView.swift:85)
- [MOMENTO/Views/ItemDetail/NotesTabView.swift:64](MOMENTO/Views/ItemDetail/NotesTabView.swift:64)

---

## Test coverage

25 tests across 6 XCTest files. What is covered is covered well — the path-traversal tests in
`SecurityHardeningTests` and the GPS-stripping test are exactly the right things to pin down, and
`CaptureGuidanceEngineTests` shows the value of having extracted that logic.

Not covered at all:

- `CaptureViewModel` — the most complex file in the project, zero tests on its state machine
- `ItemDetailViewModel` — autosave debounce, delete-then-remove-file ordering
- `PhotoSetReconstructionViewModel` — readiness rules, now including the new capability gate
- `AudioRecordingService` — both bugs in H1/H2 would have been caught by one test
- PDF export *content* — only emptiness and error cases are asserted, never what is drawn
- `DeviceCapability` — thin, but the branching copy is user-facing

The suite uses XCTest. Swift Testing is available on the iOS 26 toolchain and would suit the
value-type logic here (`CaptureGuidanceEngine`, `CaptureSetQualityService.evaluate`,
`StringArrayValueTransformer`) much better with parameterized cases.

## Things done well, worth not regressing

- `FileStorageService.resolveURL` does real path containment, with `..`/absolute/`~` rejection,
  and it is tested from both directions. One residual gap: `standardizedFileURL` does not resolve
  symlinks, so a symlink planted inside the managed directory could still escape. Low threat in
  an app-private container.
- Capture failure modes are modelled as a typed `CaptureError` with user-actionable messages, not
  swallowed or stringified at the throw site.
- `ThumbnailService` prefers a source photo over rendering the fresh USDZ, with the reason written
  down in a comment. That is a hard-won lesson preserved correctly.
- The HTTPS-only, off-by-default, explicitly-consented cloud suggestion design is genuinely
  privacy-respecting, and the endpoint validation is tested.
- `startupResult` turns a container failure into a real UI state instead of a crash on launch.

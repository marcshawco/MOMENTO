import RealityKit
import AVFoundation
import SwiftData
import SwiftUI
import os

// MARK: - Capture Flow State

enum CaptureFlowState {
    case idle
    case initializing
    case ready
    case detecting
    case capturing
    case finishing
    case completed
    case reconstructing(progress: Double)
    case generatingThumbnail
    case saved
    case failed(CaptureError)
    case unsupported(String)

    var isCapturing: Bool {
        switch self {
        case .ready, .detecting, .capturing, .finishing:
            true
        default:
            false
        }
    }

    var isProcessing: Bool {
        switch self {
        case .reconstructing, .generatingThumbnail:
            true
        default:
            false
        }
    }
}

// MARK: - Capture Error

enum CaptureError: Error, LocalizedError {
    case deviceNotSupported
    case insufficientDiskSpace(availableMB: Int)
    case cameraPermissionDenied
    case initializationTimedOut
    case captureDidNotBegin
    case appMovedToBackground
    case captureSetQualityInsufficient(CaptureSetQualityReport)
    case sessionFailed(any Error)
    case reconstructionFailed(any Error)
    case thumbnailGenerationFailed(any Error)
    case fileOperationFailed(any Error)

    var errorDescription: String? {
        switch self {
        case .deviceNotSupported:
            "This device doesn't support 3D object scanning. A device with LiDAR is required."
        case .insufficientDiskSpace(let mb):
            "Not enough storage space. \(mb) MB available, \(AppConstants.Limits.minimumDiskSpaceMB) MB required."
        case .cameraPermissionDenied:
            "Camera access is required for 3D scanning. Enable Camera access for Momento in Settings."
        case .initializationTimedOut:
            "Camera initialization timed out. Close other camera apps and try again."
        case .captureDidNotBegin:
            "Scanning did not start. Reposition the object and try again."
        case .appMovedToBackground:
            "Capture was interrupted because Momento moved to the background. Keep the app open while scanning."
        case .captureSetQualityInsufficient(let report):
            "The captured photo set is not ready for reconstruction. \(report.userMessage)"
        case .sessionFailed(let error):
            "Capture failed: \(error.localizedDescription)"
        case .reconstructionFailed(let error):
            "3D reconstruction failed: \(error.localizedDescription)"
        case .thumbnailGenerationFailed:
            "Failed to generate preview image. The 3D model was saved successfully."
        case .fileOperationFailed(let error):
            "File operation failed: \(error.localizedDescription)"
        }
    }
}

// MARK: - CaptureViewModel

@MainActor
@Observable
final class CaptureViewModel {

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Momento", category: "Capture")

    // MARK: - Published State

    var flowState: CaptureFlowState = .idle
    var session: ObjectCaptureSession?
    var feedbackMessages: Set<ObjectCaptureSession.Feedback> = []
    var numberOfShotsTaken: Int = 0
    var userCompletedScanPass: Bool = false
    var hasUserStartedScan: Bool = false
    var isTorchOn: Bool = false
    var canRequestImageCapture: Bool = false
    var cameraTracking: ObjectCaptureSession.Tracking = .notAvailable
    var createdItemId: UUID?
    var detectionStatusText: String = "Align object on a flat surface to begin."
    var showAreaModeFallback: Bool = false
    var isHandheldModeActive: Bool = false
    var guidanceNow: Date = .now
    var debugEvents: [String] = []

    // MARK: - Internal State

    private var sessionId: String = ""
    private var imagesDirectoryURL: URL?
    private var checkpointDirectoryURL: URL?
    private var modelContext: ModelContext?

    private var stateObservationTask: Task<Void, Never>?
    private var feedbackObservationTask: Task<Void, Never>?
    private var shotCountTask: Task<Void, Never>?
    private var scanPassTask: Task<Void, Never>?
    private var canRequestImageCaptureTask: Task<Void, Never>?
    private var cameraTrackingTask: Task<Void, Never>?
    private var reconstructionTask: Task<Void, Never>?
    private var initializationTimeoutTask: Task<Void, Never>?
    private var captureStartWatchdogTask: Task<Void, Never>?
    private var detectRecoveryTask: Task<Void, Never>?
    private var guidanceTickerTask: Task<Void, Never>?
    private var pendingAutoStartCapture = false
    private var lastShotCount = 0
    private var lastShotAcceptedAt = Date.now
    private var lastLoggedCanRequestImageCapture: Bool?
    private var lastLoggedTrackingText = ""

    deinit {}

    // MARK: - Public API

    /// Call before starting to provide the model context for saving items.
    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// Starts the full capture session. Checks device support and disk space first.
    func startSession() async {
        guard case .idle = flowState else { return }

        // Check device support
        guard ObjectCaptureSession.isSupported else {
            flowState = .unsupported(
                "This device does not support 3D object scanning. " +
                "A device with LiDAR sensor is required (iPhone 12 Pro or later)."
            )
            return
        }

        // Check disk space
        guard FileStorageService.shared.hasSufficientDiskSpace else {
            let available = FileStorageService.shared.availableDiskSpaceMB()
            flowState = .failed(.insufficientDiskSpace(availableMB: available))
            return
        }

        // Camera preflight prevents opaque ObjectCapture failures.
        let hasCameraAccess = await ensureCameraAccess()
        guard hasCameraAccess else {
            flowState = .failed(.cameraPermissionDenied)
            return
        }

        flowState = .initializing

        do {
            // Create temporary directories for this capture session
            sessionId = UUID().uuidString
            let tempDir = try FileStorageService.shared.captureTempDirectory(sessionId: sessionId)
            let imagesDir = tempDir.appendingPathComponent("images", isDirectory: true)
            let checkpointDir = tempDir.appendingPathComponent("checkpoints", isDirectory: true)
            try FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: checkpointDir, withIntermediateDirectories: true)
            imagesDirectoryURL = imagesDir
            checkpointDirectoryURL = checkpointDir
            lastShotCount = 0
            lastShotAcceptedAt = .now
            guidanceNow = .now

            // Create and start the capture session
            let captureSession = ObjectCaptureSession()
            var config = ObjectCaptureSession.Configuration()
            // Prioritize capture fidelity over speed/storage.
            config.isOverCaptureEnabled = true
            config.checkpointDirectory = checkpointDir
            session = captureSession

            // Observe state before start to avoid missing early state transitions.
            observeSession(captureSession)
            captureSession.start(imagesDirectory: imagesDir, configuration: config)
            beginInitializationTimeoutGuard()
            startGuidanceTicker()

            logger.info("Capture session started. Session ID: \(self.sessionId)")
        } catch {
            flowState = .failed(.fileOperationFailed(error))
            cleanup()
            logger.error("Failed to start capture session: \(error.localizedDescription)")
        }
    }

    /// Tells the session the user has finished scanning.
    func finishCapture() {
        guard let session else { return }
        session.finish()
        logger.info("User finished capture")
    }

    func beginUserScan() {
        guard let session else { return }
        guard case .normal = cameraTracking else {
            detectionStatusText = "Move to a textured, well-lit flat surface until tracking is stable."
            return
        }
        hasUserStartedScan = true
        isHandheldModeActive = false
        pendingAutoStartCapture = true
        showAreaModeFallback = false
        let detectingStarted = session.startDetecting()
        if !detectingStarted {
            detectionStatusText = "No object found automatically. Place the box over the object, then continue."
        } else {
            detectionStatusText = "Detecting object..."
        }
        beginCaptureStartWatchdog()
        beginDetectRecoveryWatchdog()
        logger.info("User requested scan start. detectingStarted=\(detectingStarted)")
        maybeStartCapturingIfReady()
    }

    func resetDetectionAndRetry() {
        guard let session else { return }
        _ = session.resetDetection()
        isHandheldModeActive = false
        pendingAutoStartCapture = session.startDetecting()
        showAreaModeFallback = false
        detectionStatusText = "Resetting detection..."
        beginDetectRecoveryWatchdog()
        logger.info("Manual detection reset requested")
    }

    func startAreaModeCapture() {
        guard let session else { return }
        guard case .normal = cameraTracking else {
            detectionStatusText = "Tracking is limited. Add light/texture, then try handheld scan again."
            return
        }
        hasUserStartedScan = true
        isHandheldModeActive = true
        pendingAutoStartCapture = false
        showAreaModeFallback = false
        detectionStatusText = "Handheld scan started. Keep the object centered and rotate it slowly."
        appendDebugEvent("handheldModeStartRequested")
        session.startCapturing()
        logger.info("User requested handheld capture")
    }

    func requestSingleImageCapture() {
        guard let session else { return }
        guard canRequestImageCapture else { return }
        session.requestImageCapture()
        detectionStatusText = isHandheldModeActive
            ? "Captured shot. Rotate the object slightly and capture the next angle."
            : "Captured shot. Continue moving around the object."
    }

    var shouldShowStartScanButton: Bool {
        if case .ready = flowState {
            return true
        }
        return false
    }

    var startScanButtonTitle: String {
        hasUserStartedScan ? "Start Scanning Again" : "Start Scanning"
    }

    var canStartScan: Bool {
        guard case .ready = flowState else { return false }
        if case .normal = cameraTracking {
            return true
        }
        return false
    }

    var estimatedCaptureProgress: Double {
        if userCompletedScanPass {
            return 1.0
        }
        // Heuristic coverage estimate for UX feedback during capture.
        let targetShots = 45.0
        return min(Double(numberOfShotsTaken) / targetShots, 0.95)
    }

    var estimatedCaptureProgressPercentText: String {
        "\(Int((estimatedCaptureProgress * 100).rounded()))%"
    }

    var shotStallDuration: TimeInterval {
        guard case .capturing = flowState else { return 0 }
        return max(0, guidanceNow.timeIntervalSince(lastShotAcceptedAt))
    }

    var currentGuidance: CaptureGuidance {
        let snapshot = CaptureGuidanceSnapshot(
            flowState: guidanceFlowState,
            trackingIsNormal: isTrackingNormal,
            trackingDescription: planeStatusText,
            canRequestImageCapture: canRequestImageCapture,
            shotCount: numberOfShotsTaken,
            shotStallSeconds: shotStallDuration,
            coverage: estimatedCaptureProgress,
            userCompletedScanPass: userCompletedScanPass,
            hasLowLightFeedback: hasFeedback(.environmentLowLight) || hasFeedback(.environmentTooDark),
            hasMovingTooFastFeedback: hasFeedback(.movingTooFast),
            hasTooCloseFeedback: hasFeedback(.objectTooClose),
            hasTooFarFeedback: hasFeedback(.objectTooFar),
            hasOutOfFieldOfViewFeedback: hasFeedback(.outOfFieldOfView)
        )
        return CaptureGuidanceEngine.guidance(for: snapshot)
    }

    var captureProgressHelpText: String {
        currentGuidance.detail
    }

    var planeStatusText: String {
        switch cameraTracking {
        case .normal:
            return canRequestImageCapture ? "Plane locked" : "Tracking stable, waiting for bounding box"
        case .limited(let reason):
            switch reason {
            case .insufficientFeatures:
                return "Need more texture/light"
            case .excessiveMotion:
                return "Move slower"
            case .relocalizing:
                return "Re-localizing scene"
            case .initializing:
                return "Initializing tracking"
            @unknown default:
                return "Tracking limited"
            }
        case .notAvailable:
            return "No plane lock"
        @unknown default:
            return "Tracking unknown"
        }
    }

    var shouldShowManualCaptureButton: Bool {
        switch flowState {
        case .detecting, .capturing:
            return canRequestImageCapture
        default:
            return false
        }
    }

    var shouldShowResetDetectionButton: Bool {
        switch flowState {
        case .ready, .detecting:
            return hasUserStartedScan && !canRequestImageCapture
        default:
            return false
        }
    }

    var shouldShowAreaModeButton: Bool {
        switch flowState {
        case .ready:
            return canStartScan && !hasUserStartedScan
        case .detecting:
            return hasUserStartedScan && showAreaModeFallback
        default:
            return false
        }
    }

    var debugFlowStateText: String {
        switch flowState {
        case .idle: "idle"
        case .initializing: "initializing"
        case .ready: "ready"
        case .detecting: "detecting"
        case .capturing: "capturing"
        case .finishing: "finishing"
        case .completed: "completed"
        case .reconstructing(let progress): "reconstructing \(Int(progress * 100))%"
        case .generatingThumbnail: "generatingThumbnail"
        case .saved: "saved"
        case .failed: "failed"
        case .unsupported: "unsupported"
        }
    }

    var debugTrackingText: String {
        switch cameraTracking {
        case .normal:
            return "normal"
        case .limited(let reason):
            switch reason {
            case .initializing:
                return "limited(initializing)"
            case .insufficientFeatures:
                return "limited(insufficientFeatures)"
            case .excessiveMotion:
                return "limited(excessiveMotion)"
            case .relocalizing:
                return "limited(relocalizing)"
            @unknown default:
                return "limited(unknown)"
            }
        case .notAvailable:
            return "notAvailable"
        @unknown default:
            return "unknown"
        }
    }

    var debugCanRequestCaptureText: String {
        canRequestImageCapture ? "true" : "false"
    }

    var debugPendingAutoStartText: String {
        pendingAutoStartCapture ? "true" : "false"
    }

    /// Cancels the capture and cleans up.
    func cancel() {
        session?.cancel()
        cancelAllTasks()
        cleanup()
        logger.info("Capture cancelled")
    }

    /// Capture/reconstruction must run in foreground to avoid GPU background-execution aborts.
    func handleBackgroundTransition() {
        let isInitializing: Bool
        if case .initializing = flowState {
            isInitializing = true
        } else {
            isInitializing = false
        }
        let isBusy = flowState.isCapturing || flowState.isProcessing || isInitializing
        guard isBusy else { return }
        session?.cancel()
        cancelAllTasks()
        cleanup()
        flowState = .failed(.appMovedToBackground)
        logger.warning("Capture cancelled due to background transition")
    }

    /// Retries from a failed state.
    func retry() {
        cancelAllTasks()
        cleanup()
        session = nil
        flowState = .idle
        Task { [weak self] in
            guard let self else { return }
            await self.startSession()
        }
    }

    var isTorchSupported: Bool {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            return false
        }
        return device.hasTorch
    }

    func toggleTorch() {
        let requestedState = !isTorchOn
        if setTorchEnabled(requestedState) {
            isTorchOn = requestedState
        }
    }

    // MARK: - Session Observation

    private func observeSession(_ captureSession: ObjectCaptureSession) {
        stateObservationTask = Task { [weak self] in
            for await newState in captureSession.stateUpdates {
                guard let self else { return }
                self.handleStateChange(newState)
            }
        }

        feedbackObservationTask = Task { [weak self] in
            for await feedback in captureSession.feedbackUpdates {
                guard let self else { return }
                self.feedbackMessages = feedback
            }
        }

        shotCountTask = Task { [weak self] in
            for await count in captureSession.numberOfShotsTakenUpdates {
                guard let self else { return }
                if count > self.lastShotCount {
                    self.lastShotAcceptedAt = .now
                }
                self.lastShotCount = count
                self.numberOfShotsTaken = count
            }
        }

        scanPassTask = Task { [weak self] in
            for await completed in captureSession.userCompletedScanPassUpdates {
                guard let self else { return }
                self.userCompletedScanPass = completed
            }
        }

        canRequestImageCaptureTask = Task { [weak self] in
            for await canRequest in captureSession.canRequestImageCaptureUpdates {
                guard let self else { return }
                self.canRequestImageCapture = canRequest
                if canRequest {
                    self.cancelDetectRecoveryWatchdog()
                    self.detectionStatusText = "Bounding box settled. Ready to capture."
                }
                if self.lastLoggedCanRequestImageCapture != canRequest {
                    self.appendDebugEvent("canRequestImageCapture=\(canRequest)")
                    self.lastLoggedCanRequestImageCapture = canRequest
                }
                self.maybeStartCapturingIfReady()
            }
        }

        cameraTrackingTask = Task { [weak self] in
            for await tracking in captureSession.cameraTrackingUpdates {
                guard let self else { return }
                self.cameraTracking = tracking
                let trackingText = self.debugTrackingText
                if trackingText != self.lastLoggedTrackingText {
                    self.appendDebugEvent("tracking=\(trackingText)")
                    self.lastLoggedTrackingText = trackingText
                }
                if case .ready = self.flowState, self.canStartScan == false {
                    self.detectionStatusText = "Move to a textured, well-lit flat surface to lock tracking."
                }
            }
        }
    }

    private func handleStateChange(_ newState: ObjectCaptureSession.CaptureState) {
        logger.info("Capture state update: \(String(describing: newState))")
        appendDebugEvent("state=\(String(describing: newState))")
        switch newState {
        case .initializing:
            flowState = .initializing
        case .ready:
            cancelInitializationTimeoutGuard()
            flowState = .ready
            maybeStartCapturingIfReady()
        case .detecting:
            cancelInitializationTimeoutGuard()
            cancelCaptureStartWatchdog()
            hasUserStartedScan = true
            detectionStatusText = canRequestImageCapture
                ? "Object detected. Preparing capture..."
                : "Adjust bounding box until object sits on a stable surface."
            flowState = .detecting
            maybeStartCapturingIfReady()
        case .capturing:
            cancelInitializationTimeoutGuard()
            cancelCaptureStartWatchdog()
            cancelDetectRecoveryWatchdog()
            hasUserStartedScan = true
            pendingAutoStartCapture = false
            showAreaModeFallback = false
            detectionStatusText = "Capturing frames..."
            flowState = .capturing
        case .finishing:
            cancelInitializationTimeoutGuard()
            cancelCaptureStartWatchdog()
            cancelDetectRecoveryWatchdog()
            hasUserStartedScan = true
            pendingAutoStartCapture = false
            showAreaModeFallback = false
            flowState = .finishing
        case .completed:
            cancelInitializationTimeoutGuard()
            cancelCaptureStartWatchdog()
            cancelDetectRecoveryWatchdog()
            pendingAutoStartCapture = false
            showAreaModeFallback = false
            flowState = .completed
            logger.info("Capture completed. Starting reconstruction.")
            startReconstruction()
        case .failed(let error):
            cancelInitializationTimeoutGuard()
            cancelCaptureStartWatchdog()
            cancelDetectRecoveryWatchdog()
            pendingAutoStartCapture = false
            showAreaModeFallback = false
            flowState = .failed(.sessionFailed(error))
            cancelAllTasks()
            cleanup()
            logger.error("Capture session failed: \(error.localizedDescription)")
        @unknown default:
            break
        }
    }

    // MARK: - Reconstruction

    private func startReconstruction() {
        guard let imagesDir = imagesDirectoryURL else {
            flowState = .failed(.fileOperationFailed(
                NSError(domain: "Momento", code: -1, userInfo: [NSLocalizedDescriptionKey: "Images directory not found"])
            ))
            return
        }

        let itemId = UUID()
        reconstructionTask = Task { [weak self] in
            guard let self else { return }

            do {
                let outputURL = try FileStorageService.shared.modelsDirectory()
                    .appendingPathComponent("\(itemId.uuidString).usdz")

                let qualityReport = await CaptureSetQualityService.shared.assessImageSet(at: imagesDir)
                guard qualityReport.isReconstructionReady else {
                    self.flowState = .failed(.captureSetQualityInsufficient(qualityReport))
                    self.cancelAllTasks()
                    self.cleanup()
                    return
                }

                self.flowState = .reconstructing(progress: 0)
                logger.info("Starting reconstruction. Output: \(outputURL.lastPathComponent)")

                // Create and start PhotogrammetrySession
                // NOTE: PhotogrammetrySession.init and process() are nonisolated but quick.
                // The heavy work happens asynchronously via the outputs stream.
                var reconstructionConfig: PhotogrammetrySession.Configuration
                if let checkpointDirectoryURL = self.checkpointDirectoryURL {
                    reconstructionConfig = PhotogrammetrySession.Configuration(checkpointDirectory: checkpointDirectoryURL)
                } else {
                    reconstructionConfig = PhotogrammetrySession.Configuration()
                }
                reconstructionConfig.featureSensitivity = .high
                reconstructionConfig.sampleOrdering = .sequential
                let pgSession = try PhotogrammetrySession(input: imagesDir, configuration: reconstructionConfig)
                try pgSession.process(requests: [
                    // Uncertain Apple API detail: iOS currently supports .reduced only; request it explicitly as the maximum on-device detail level.
                    .modelFile(url: outputURL, detail: .reduced)
                ])

                // Monitor reconstruction progress
                for try await output in pgSession.outputs {
                    switch output {
                    case .requestProgress(_, let fractionComplete):
                        self.flowState = .reconstructing(progress: fractionComplete)

                    case .requestComplete(_, .modelFile(let url)):
                        logger.info("Reconstruction complete: \(url.lastPathComponent)")
                        await self.handleReconstructionComplete(
                            modelURL: url,
                            itemId: itemId
                        )
                        return

                    case .requestError(_, let error):
                        self.flowState = .failed(.reconstructionFailed(error))
                        self.cancelAllTasks()
                        self.cleanup()
                        return

                    case .processingCancelled:
                        self.cancelAllTasks()
                        self.cleanup()
                        logger.info("Reconstruction cancelled")
                        return

                    default:
                        break
                    }
                }

            } catch {
                self.flowState = .failed(.reconstructionFailed(error))
                self.cancelAllTasks()
                self.cleanup()
                logger.error("Reconstruction failed: \(error.localizedDescription)")
            }
        }
    }

    private func handleReconstructionComplete(modelURL: URL, itemId: UUID) async {
        flowState = .generatingThumbnail

        // Generate a stable preview thumbnail. Prefer a captured source photo so completing a
        // reconstruction never has to immediately load the fresh USDZ into a 3D renderer.
        var thumbnailFileName: String?
        do {
            let thumbData: Data
            if let imagesDirectoryURL {
                thumbData = try await ThumbnailService.shared.generateCaptureThumbnail(from: imagesDirectoryURL)
            } else {
                thumbData = try await ThumbnailService.shared.generateThumbnail(from: modelURL)
            }
            thumbnailFileName = try FileStorageService.shared.saveFile(
                data: thumbData,
                directory: AppConstants.Storage.thumbnailsFolder,
                fileName: "\(itemId.uuidString).png"
            )
            logger.info("Thumbnail generated")
        } catch {
            // Thumbnail failure is non-fatal — item is still saved without a preview
            logger.warning("Thumbnail generation failed: \(error.localizedDescription)")
        }

        let suggestion: ObjectMetadataSuggestion?
        if let imagesDir = imagesDirectoryURL {
            suggestion = await ObjectIntelligenceService.shared.suggestMetadata(from: imagesDir)
        } else {
            suggestion = nil
        }

        // Save to SwiftData
        let modelFileName = "\(AppConstants.Storage.modelsFolder)/\(itemId.uuidString).usdz"
        saveItem(
            id: itemId,
            modelFileName: modelFileName,
            thumbnailFileName: thumbnailFileName,
            metadataSuggestion: suggestion
        )

        // Clean up temporary capture data
        cleanup()
    }

    private func saveItem(
        id: UUID,
        modelFileName: String,
        thumbnailFileName: String?,
        metadataSuggestion: ObjectMetadataSuggestion?
    ) {
        guard let modelContext else {
            logger.error("ModelContext not configured. Cannot save item.")
            flowState = .failed(.fileOperationFailed(
                NSError(domain: "Momento", code: -2, userInfo: [NSLocalizedDescriptionKey: "Database not available"])
            ))
            return
        }

        let item = CollectionItem(
            id: id,
            title: metadataSuggestion?.title ?? "Untitled Scan",
            tags: metadataSuggestion?.tags ?? [],
            collectionName: metadataSuggestion?.collectionName ?? "",
            modelFileName: modelFileName,
            thumbnailFileName: thumbnailFileName
        )
        modelContext.insert(item)
        do {
            try modelContext.save()
        } catch {
            flowState = .failed(.fileOperationFailed(error))
            logger.error("Failed to save item: \(error.localizedDescription)")
            return
        }

        createdItemId = item.id
        flowState = .saved

        logger.info("Item saved: \(item.id)")
    }

    // MARK: - Cleanup

    private func cleanup() {
        if isTorchOn {
            _ = setTorchEnabled(false)
            isTorchOn = false
        }
        if !sessionId.isEmpty {
            FileStorageService.shared.cleanupCaptureTemp(sessionId: sessionId)
        }
        sessionId = ""
        imagesDirectoryURL = nil
        checkpointDirectoryURL = nil
        session = nil
        feedbackMessages = []
        numberOfShotsTaken = 0
        userCompletedScanPass = false
        canRequestImageCapture = false
        cameraTracking = .notAvailable
        hasUserStartedScan = false
        isHandheldModeActive = false
        pendingAutoStartCapture = false
        showAreaModeFallback = false
        lastShotCount = 0
        lastShotAcceptedAt = .now
        guidanceNow = .now
        lastLoggedCanRequestImageCapture = nil
        lastLoggedTrackingText = ""
        debugEvents = []
        detectionStatusText = "Align object on a flat surface to begin."
    }

    private func cancelAllTasks() {
        stateObservationTask?.cancel()
        feedbackObservationTask?.cancel()
        shotCountTask?.cancel()
        scanPassTask?.cancel()
        canRequestImageCaptureTask?.cancel()
        cameraTrackingTask?.cancel()
        reconstructionTask?.cancel()
        initializationTimeoutTask?.cancel()
        captureStartWatchdogTask?.cancel()
        detectRecoveryTask?.cancel()
        guidanceTickerTask?.cancel()
        stateObservationTask = nil
        feedbackObservationTask = nil
        shotCountTask = nil
        scanPassTask = nil
        canRequestImageCaptureTask = nil
        cameraTrackingTask = nil
        reconstructionTask = nil
        initializationTimeoutTask = nil
        captureStartWatchdogTask = nil
        detectRecoveryTask = nil
        guidanceTickerTask = nil
    }

    private func ensureCameraAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            true
        case .notDetermined:
            await AVCaptureDevice.requestAccess(for: .video)
        case .denied, .restricted:
            false
        @unknown default:
            false
        }
    }

    private func beginInitializationTimeoutGuard() {
        initializationTimeoutTask?.cancel()
        initializationTimeoutTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(15))
            guard let self else { return }
            guard case .initializing = self.flowState else { return }

            self.session?.cancel()
            self.cancelAllTasks()
            self.cleanup()
            self.flowState = .failed(.initializationTimedOut)
            self.logger.error("Capture initialization timed out")
        }
    }

    private func cancelInitializationTimeoutGuard() {
        initializationTimeoutTask?.cancel()
        initializationTimeoutTask = nil
    }

    private func beginCaptureStartWatchdog() {
        captureStartWatchdogTask?.cancel()
        captureStartWatchdogTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            guard let self else { return }
            guard case .ready = self.flowState, self.numberOfShotsTaken == 0 else { return }
            self.pendingAutoStartCapture = false
            self.detectionStatusText = "No stable plane found. Reposition object and tap Reset Detection."
            self.logger.warning("Capture still in ready state due to missing plane/bounds")
        }
    }

    private func cancelCaptureStartWatchdog() {
        captureStartWatchdogTask?.cancel()
        captureStartWatchdogTask = nil
    }

    private func beginDetectRecoveryWatchdog() {
        detectRecoveryTask?.cancel()
        detectRecoveryTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(10))
            guard let self else { return }
            guard self.hasUserStartedScan else { return }
            guard !self.canRequestImageCapture else { return }

            switch self.flowState {
            case .ready, .detecting:
                break
            default:
                return
            }

            self.pendingAutoStartCapture = false
            self.showAreaModeFallback = true
            self.detectionStatusText = "Still no plane lock. Try better lighting/texture and tap Reset Detection."
            self.logger.warning("Detection watchdog fired without plane lock")
        }
    }

    private func cancelDetectRecoveryWatchdog() {
        detectRecoveryTask?.cancel()
        detectRecoveryTask = nil
    }

    private func maybeStartCapturingIfReady() {
        guard pendingAutoStartCapture else { return }
        guard canRequestImageCapture else { return }
        guard let session else { return }
        guard case .detecting = flowState else { return }

        session.startCapturing()
        detectionStatusText = "Bounding box settled. Capturing frames..."
        pendingAutoStartCapture = false
    }

    private var isTrackingNormal: Bool {
        if case .normal = cameraTracking {
            return true
        }
        return false
    }

    private var guidanceFlowState: CaptureGuidanceFlowState {
        switch flowState {
        case .idle:
            return .idle
        case .initializing:
            return .initializing
        case .ready:
            return .ready
        case .detecting:
            return .detecting
        case .capturing:
            return .capturing
        case .finishing:
            return .finishing
        case .completed:
            return .completed
        case .reconstructing:
            return .reconstructing
        case .generatingThumbnail:
            return .generatingThumbnail
        case .saved:
            return .saved
        case .failed:
            return .failed
        case .unsupported:
            return .unsupported
        }
    }

    private func hasFeedback(_ feedback: ObjectCaptureSession.Feedback) -> Bool {
        feedbackMessages.contains(feedback)
    }

    private func startGuidanceTicker() {
        guidanceTickerTask?.cancel()
        guidanceTickerTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled else { return }
                self.guidanceNow = .now
            }
        }
    }

    @discardableResult
    private func setTorchEnabled(_ enabled: Bool) -> Bool {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              device.hasTorch else {
            return false
        }

        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }

            if enabled {
                let level = min(0.5, AVCaptureDevice.maxAvailableTorchLevel)
                try device.setTorchModeOn(level: level)
            } else {
                device.torchMode = .off
            }
            return true
        } catch {
            logger.warning("Torch toggle failed: \(error.localizedDescription)")
            return false
        }
    }

    private func appendDebugEvent(_ event: String) {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let timestamp = formatter.string(from: Date())
        debugEvents.append("[\(timestamp)] \(event)")
        if debugEvents.count > 12 {
            debugEvents.removeFirst(debugEvents.count - 12)
        }
    }
}

// MARK: - Feedback Helpers

extension ObjectCaptureSession.Feedback {
    var userMessage: String {
        switch self {
        case .objectTooClose:
            "Move farther from the object"
        case .objectTooFar:
            "Move closer to the object"
        case .movingTooFast:
            "Slow down"
        case .environmentLowLight:
            "More light needed"
        case .environmentTooDark:
            "Environment is too dark"
        case .outOfFieldOfView:
            "Point camera at the object"
        case .objectNotFlippable:
            "Object cannot be flipped"
        case .overCapturing:
            "Sufficient data captured"
        case .objectNotDetected:
            "No object detected"
        @unknown default:
            "Adjust position"
        }
    }

    var systemImage: String {
        switch self {
        case .objectTooClose: "arrow.up.backward.and.arrow.down.forward"
        case .objectTooFar: "arrow.down.forward.and.arrow.up.backward"
        case .movingTooFast: "tortoise"
        case .environmentLowLight, .environmentTooDark: "sun.max"
        case .outOfFieldOfView: "viewfinder"
        case .objectNotFlippable: "arrow.triangle.2.circlepath"
        case .overCapturing: "checkmark.circle"
        case .objectNotDetected: "cube.transparent"
        @unknown default: "exclamationmark.triangle"
        }
    }
}

import RealityKit
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

@Observable
final class CaptureViewModel {

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Momento", category: "Capture")

    // MARK: - Published State

    var flowState: CaptureFlowState = .idle
    var session: ObjectCaptureSession?
    var feedbackMessages: Set<ObjectCaptureSession.Feedback> = []
    var numberOfShotsTaken: Int = 0
    var userCompletedScanPass: Bool = false
    var createdItemId: UUID?

    // MARK: - Internal State

    private var sessionId: String = ""
    private var imagesDirectoryURL: URL?
    private var modelContext: ModelContext?

    private var stateObservationTask: Task<Void, Never>?
    private var feedbackObservationTask: Task<Void, Never>?
    private var shotCountTask: Task<Void, Never>?
    private var scanPassTask: Task<Void, Never>?
    private var reconstructionTask: Task<Void, Never>?

    deinit {
        cancelAllTasks()
    }

    // MARK: - Public API

    /// Call before starting to provide the model context for saving items.
    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    /// Starts the full capture session. Checks device support and disk space first.
    func startSession() {
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

        flowState = .initializing

        do {
            // Create temporary directories for this capture session
            sessionId = UUID().uuidString
            let tempDir = try FileStorageService.shared.captureTempDirectory(sessionId: sessionId)
            let imagesDir = tempDir.appendingPathComponent("images", isDirectory: true)
            try FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
            imagesDirectoryURL = imagesDir

            // Create and start the capture session
            let captureSession = ObjectCaptureSession()
            var config = ObjectCaptureSession.Configuration()
            config.isOverCaptureEnabled = true
            captureSession.start(imagesDirectory: imagesDir, configuration: config)

            session = captureSession

            // Observe session state changes
            observeSession(captureSession)

            logger.info("Capture session started. Session ID: \(self.sessionId)")
        } catch {
            flowState = .failed(.fileOperationFailed(error))
            logger.error("Failed to start capture session: \(error.localizedDescription)")
        }
    }

    /// Tells the session the user has finished scanning.
    func finishCapture() {
        guard let session else { return }
        session.finish()
        logger.info("User finished capture")
    }

    /// Cancels the capture and cleans up.
    func cancel() {
        session?.cancel()
        cancelAllTasks()
        cleanup()
        logger.info("Capture cancelled")
    }

    /// Retries from a failed state.
    func retry() {
        cancelAllTasks()
        cleanup()
        session = nil
        flowState = .idle
        startSession()
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
                self.numberOfShotsTaken = count
            }
        }

        scanPassTask = Task { [weak self] in
            for await completed in captureSession.userCompletedScanPassUpdates {
                guard let self else { return }
                self.userCompletedScanPass = completed
            }
        }
    }

    private func handleStateChange(_ newState: ObjectCaptureSession.CaptureState) {
        switch newState {
        case .initializing:
            flowState = .initializing
        case .ready:
            flowState = .ready
        case .detecting:
            flowState = .detecting
        case .capturing:
            flowState = .capturing
        case .finishing:
            flowState = .finishing
        case .completed:
            flowState = .completed
            logger.info("Capture completed. Starting reconstruction.")
            startReconstruction()
        case .failed(let error):
            flowState = .failed(.sessionFailed(error))
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
        flowState = .reconstructing(progress: 0)

        reconstructionTask = Task { [weak self] in
            guard let self else { return }

            do {
                let outputURL = try FileStorageService.shared.modelsDirectory()
                    .appendingPathComponent("\(itemId.uuidString).usdz")

                logger.info("Starting reconstruction. Output: \(outputURL.lastPathComponent)")

                // Create and start PhotogrammetrySession
                // NOTE: PhotogrammetrySession.init and process() are nonisolated but quick.
                // The heavy work happens asynchronously via the outputs stream.
                let pgSession = try PhotogrammetrySession(input: imagesDir)
                try pgSession.process(requests: [
                    .modelFile(url: outputURL)
                    // iOS only supports .reduced detail level
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
                        return

                    case .processingCancelled:
                        logger.info("Reconstruction cancelled")
                        return

                    default:
                        break
                    }
                }

            } catch {
                self.flowState = .failed(.reconstructionFailed(error))
                logger.error("Reconstruction failed: \(error.localizedDescription)")
            }
        }
    }

    private func handleReconstructionComplete(modelURL: URL, itemId: UUID) async {
        flowState = .generatingThumbnail

        // Generate thumbnail from the USDZ
        var thumbnailFileName: String?
        do {
            let thumbData = try await ThumbnailService.shared.generateThumbnail(from: modelURL)
            thumbnailFileName = try FileStorageService.shared.saveFile(
                data: thumbData,
                directory: AppConstants.Storage.thumbnailsFolder,
                fileName: "\(itemId.uuidString).jpg"
            )
            logger.info("Thumbnail generated")
        } catch {
            // Thumbnail failure is non-fatal — item is still saved without a preview
            logger.warning("Thumbnail generation failed: \(error.localizedDescription)")
        }

        // Save to SwiftData
        let modelFileName = "\(AppConstants.Storage.modelsFolder)/\(itemId.uuidString).usdz"
        saveItem(
            id: itemId,
            modelFileName: modelFileName,
            thumbnailFileName: thumbnailFileName
        )

        // Clean up temporary capture data
        cleanup()
    }

    private func saveItem(id: UUID, modelFileName: String, thumbnailFileName: String?) {
        guard let modelContext else {
            logger.error("ModelContext not configured. Cannot save item.")
            flowState = .failed(.fileOperationFailed(
                NSError(domain: "Momento", code: -2, userInfo: [NSLocalizedDescriptionKey: "Database not available"])
            ))
            return
        }

        let item = CollectionItem(
            id: id,
            title: "Untitled Scan",
            modelFileName: modelFileName,
            thumbnailFileName: thumbnailFileName
        )
        modelContext.insert(item)

        createdItemId = item.id
        flowState = .saved

        logger.info("Item saved: \(item.id)")
    }

    // MARK: - Cleanup

    private func cleanup() {
        guard !sessionId.isEmpty else { return }
        FileStorageService.shared.cleanupCaptureTemp(sessionId: sessionId)
    }

    private func cancelAllTasks() {
        stateObservationTask?.cancel()
        feedbackObservationTask?.cancel()
        shotCountTask?.cancel()
        scanPassTask?.cancel()
        reconstructionTask?.cancel()
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

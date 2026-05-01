import Foundation
import PhotosUI
import RealityKit
import SwiftData
import SwiftUI
import os

enum PhotoSetViewpoint: String, CaseIterable, Identifiable {
    case front
    case back
    case left
    case right
    case top
    case bottom

    var id: String { rawValue }

    var title: String {
        switch self {
        case .front: "Front"
        case .back: "Back"
        case .left: "Left"
        case .right: "Right"
        case .top: "Top"
        case .bottom: "Bottom"
        }
    }

    var systemImage: String {
        switch self {
        case .front: "arrow.forward.to.line"
        case .back: "arrow.backward.to.line"
        case .left: "arrow.left.to.line"
        case .right: "arrow.right.to.line"
        case .top: "arrow.up.to.line"
        case .bottom: "arrow.down.to.line"
        }
    }

    var fileStem: String { rawValue }
}

enum PhotoSetReconstructionState: Equatable {
    case editing
    case preparing
    case reconstructing(progress: Double)
    case saving
    case saved
    case failed(String)

    var isBusy: Bool {
        switch self {
        case .preparing, .reconstructing, .saving:
            true
        case .editing, .saved, .failed:
            false
        }
    }
}

@MainActor
@Observable
final class PhotoSetReconstructionViewModel {
    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Momento", category: "PhotoSet")

    var state: PhotoSetReconstructionState = .editing
    var requiredImageData: [PhotoSetViewpoint: Data] = [:]
    var optionalImageData: [Data] = []
    var createdItemId: UUID?

    private var modelContext: ModelContext?
    private var reconstructionTask: Task<Void, Never>?
    private var sessionId = ""
    private var imagesDirectoryURL: URL?
    private var checkpointDirectoryURL: URL?

    func configure(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func setRequiredImage(_ data: Data, for viewpoint: PhotoSetViewpoint) {
        requiredImageData[viewpoint] = data
    }

    func setOptionalImages(_ data: [Data]) {
        optionalImageData = data
    }

    func removeRequiredImage(for viewpoint: PhotoSetViewpoint) {
        requiredImageData[viewpoint] = nil
    }

    func removeOptionalImage(at index: Int) {
        guard optionalImageData.indices.contains(index) else { return }
        optionalImageData.remove(at: index)
    }

    var missingRequiredViews: [PhotoSetViewpoint] {
        PhotoSetViewpoint.allCases.filter { requiredImageData[$0] == nil }
    }

    var requiredViewsComplete: Bool {
        missingRequiredViews.isEmpty
    }

    var totalImageCount: Int {
        requiredImageData.count + optionalImageData.count
    }

    var canReconstruct: Bool {
        requiredViewsComplete && totalImageCount >= 6 && !state.isBusy
    }

    var readinessText: String {
        if !requiredViewsComplete {
            let names = missingRequiredViews.map(\.title).joined(separator: ", ")
            return "Missing: \(names)"
        }

        if optionalImageData.count < 12 {
            return "Ready. Add optional detail photos for better geometry."
        }

        return "Strong photo set. Ready to reconstruct."
    }

    func reconstruct() {
        guard canReconstruct else { return }
        guard FileStorageService.shared.hasSufficientDiskSpace else {
            let available = FileStorageService.shared.availableDiskSpaceMB()
            state = .failed("Not enough storage space. \(available) MB available.")
            return
        }
        guard modelContext != nil else {
            state = .failed("Database is not available.")
            return
        }

        reconstructionTask?.cancel()
        reconstructionTask = Task { [weak self] in
            guard let self else { return }
            await self.runReconstruction()
        }
    }

    func cancel() {
        reconstructionTask?.cancel()
        cleanup()
        state = .editing
    }

    private func runReconstruction() async {
        do {
            state = .preparing
            let itemId = UUID()
            try prepareImageSet()

            guard let imagesDirectoryURL else {
                throw PhotoSetError.missingImageDirectory
            }

            let outputURL = try FileStorageService.shared.modelsDirectory()
                .appendingPathComponent("\(itemId.uuidString).usdz")

            state = .reconstructing(progress: 0)

            var configuration: PhotogrammetrySession.Configuration
            if let checkpointDirectoryURL {
                configuration = PhotogrammetrySession.Configuration(checkpointDirectory: checkpointDirectoryURL)
            } else {
                configuration = PhotogrammetrySession.Configuration()
            }
            configuration.featureSensitivity = .high
            configuration.sampleOrdering = .sequential

            let session = try PhotogrammetrySession(input: imagesDirectoryURL, configuration: configuration)
            try session.process(requests: [
                .modelFile(url: outputURL, detail: .reduced)
            ])

            for try await output in session.outputs {
                switch output {
                case .requestProgress(_, let fractionComplete):
                    state = .reconstructing(progress: fractionComplete)

                case .requestComplete(_, .modelFile(let url)):
                    try await saveItem(itemId: itemId, modelURL: url)
                    cleanup()
                    return

                case .requestError(_, let error):
                    throw error

                case .processingCancelled:
                    cleanup()
                    state = .editing
                    return

                default:
                    break
                }
            }
        } catch {
            logger.error("Photo set reconstruction failed: \(error.localizedDescription)")
            cleanup()
            state = .failed(error.localizedDescription)
        }
    }

    private func prepareImageSet() throws {
        sessionId = UUID().uuidString
        let tempDir = try FileStorageService.shared.captureTempDirectory(sessionId: sessionId)
        let imagesDir = tempDir.appendingPathComponent("images", isDirectory: true)
        let checkpointDir = tempDir.appendingPathComponent("checkpoints", isDirectory: true)
        try FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: checkpointDir, withIntermediateDirectories: true)
        imagesDirectoryURL = imagesDir
        checkpointDirectoryURL = checkpointDir

        for viewpoint in PhotoSetViewpoint.allCases {
            guard let data = requiredImageData[viewpoint] else { continue }
            let sanitized = try PhotoImportService.shared.sanitizedImageData(from: data)
            let url = imagesDir.appendingPathComponent("\(viewpoint.fileStem)-000.jpg")
            try sanitized.write(to: url, options: [.atomic])
        }

        for (index, data) in optionalImageData.enumerated() {
            let sanitized = try PhotoImportService.shared.sanitizedImageData(from: data)
            let url = imagesDir.appendingPathComponent("detail-\(String(format: "%03d", index)).jpg")
            try sanitized.write(to: url, options: [.atomic])
        }
    }

    private func saveItem(itemId: UUID, modelURL: URL) async throws {
        guard let modelContext else {
            throw PhotoSetError.missingModelContext
        }

        state = .saving

        var thumbnailFileName: String?
        if let imagesDirectoryURL {
            do {
                let thumbnailData = try await ThumbnailService.shared.generateCaptureThumbnail(from: imagesDirectoryURL)
                thumbnailFileName = try FileStorageService.shared.saveFile(
                    data: thumbnailData,
                    directory: AppConstants.Storage.thumbnailsFolder,
                    fileName: "\(itemId.uuidString).png"
                )
            } catch {
                logger.warning("Photo set thumbnail generation failed: \(error.localizedDescription)")
            }
        }

        let suggestion: ObjectMetadataSuggestion?
        if let imagesDirectoryURL {
            suggestion = await ObjectIntelligenceService.shared.suggestMetadata(from: imagesDirectoryURL)
        } else {
            suggestion = nil
        }

        let item = CollectionItem(
            id: itemId,
            title: suggestion?.title ?? "Photo Set Scan",
            tags: suggestion?.tags ?? ["photo-set"],
            collectionName: suggestion?.collectionName ?? "Collectibles",
            modelFileName: "\(AppConstants.Storage.modelsFolder)/\(modelURL.lastPathComponent)",
            thumbnailFileName: thumbnailFileName
        )
        item.provenanceNotes = "Created from required photo set views: front, back, left, right, top, bottom. Optional detail photos: \(optionalImageData.count)."

        modelContext.insert(item)
        try modelContext.save()
        createdItemId = item.id
        state = .saved
    }

    private func cleanup() {
        if !sessionId.isEmpty {
            FileStorageService.shared.cleanupCaptureTemp(sessionId: sessionId)
        }
        sessionId = ""
        imagesDirectoryURL = nil
        checkpointDirectoryURL = nil
    }

    private enum PhotoSetError: LocalizedError {
        case missingImageDirectory
        case missingModelContext

        var errorDescription: String? {
            switch self {
            case .missingImageDirectory:
                "Photo set image directory was not created."
            case .missingModelContext:
                "Database is not available."
            }
        }
    }
}

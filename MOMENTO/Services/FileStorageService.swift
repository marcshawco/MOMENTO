import Foundation
import os

struct StorageCleanupSummary: Sendable, Equatable {
    let deletedFiles: Int
    let reclaimedBytes: Int64

    var reclaimedMegabytes: Double {
        Double(reclaimedBytes) / 1_048_576.0
    }
}

/// Manages file storage for large binary assets (USDZ models, thumbnails, photos, voice memos).
/// All files are stored under Application Support/Momento/ with subdirectories per asset type.
/// SwiftData models store only relative file names; this service resolves full paths.
nonisolated final class FileStorageService: Sendable {

    static let shared = FileStorageService()

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Momento", category: "FileStorage")

    private init() {}

    // MARK: - Base Directory

    /// The root storage directory: Application Support/Momento/
    var rootDirectory: URL {
        get throws {
            let appSupport = try FileManager.default.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            return appSupport.appendingPathComponent(AppConstants.Storage.rootFolder, isDirectory: true)
        }
    }

    // MARK: - Subdirectory Access

    func modelsDirectory() throws -> URL {
        try subdirectory(AppConstants.Storage.modelsFolder)
    }

    func thumbnailsDirectory() throws -> URL {
        try subdirectory(AppConstants.Storage.thumbnailsFolder)
    }

    func photosDirectory() throws -> URL {
        try subdirectory(AppConstants.Storage.photosFolder)
    }

    func voiceMemosDirectory() throws -> URL {
        try subdirectory(AppConstants.Storage.voiceMemosFolder)
    }

    func captureTempDirectory(sessionId: String) throws -> URL {
        let base = try subdirectory(AppConstants.Storage.captureTempFolder)
        let sessionDir = base.appendingPathComponent(sessionId, isDirectory: true)
        try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
        return sessionDir
    }

    // MARK: - Path Resolution

    /// Resolves a relative file name (e.g. "Models/abc.usdz") to a full URL.
    func resolveURL(for fileName: String) throws -> URL {
        try rootDirectory.appendingPathComponent(fileName)
    }

    /// Checks if a file exists at the resolved path for a given relative name.
    func fileExists(fileName: String) -> Bool {
        guard let url = try? resolveURL(for: fileName) else { return false }
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    // MARK: - File Operations

    /// Saves data to the appropriate subdirectory. Returns the relative file name for SwiftData.
    @discardableResult
    func saveFile(data: Data, directory: String, fileName: String) throws -> String {
        let dir = try subdirectory(directory)
        let fileURL = dir.appendingPathComponent(fileName)
        try data.write(to: fileURL, options: .atomic)
        logger.info("Saved file: \(directory)/\(fileName)")
        return "\(directory)/\(fileName)"
    }

    /// Moves a file from a source URL into the managed storage. Returns the relative file name.
    @discardableResult
    func moveFile(from sourceURL: URL, directory: String, fileName: String) throws -> String {
        let dir = try subdirectory(directory)
        let destinationURL = dir.appendingPathComponent(fileName)

        if FileManager.default.fileExists(atPath: destinationURL.path(percentEncoded: false)) {
            try FileManager.default.removeItem(at: destinationURL)
        }

        try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
        logger.info("Moved file to: \(directory)/\(fileName)")
        return "\(directory)/\(fileName)"
    }

    /// Deletes a file by its relative file name.
    func deleteFile(fileName: String) {
        guard let url = try? resolveURL(for: fileName) else { return }
        do {
            try FileManager.default.removeItem(at: url)
            logger.info("Deleted file: \(fileName)")
        } catch {
            logger.warning("Failed to delete \(fileName): \(error.localizedDescription)")
        }
    }

    /// Deletes all files associated with a CollectionItem (model, thumbnail, attachments).
    func deleteFiles(for item: CollectionItem) {
        if let modelFileName = item.modelFileName {
            deleteFile(fileName: modelFileName)
        }
        if let thumbnailFileName = item.thumbnailFileName {
            deleteFile(fileName: thumbnailFileName)
        }
        for photo in item.photoAttachments {
            deleteFile(fileName: photo.fileName)
        }
        for memo in item.voiceMemos {
            deleteFile(fileName: memo.fileName)
        }
    }

    /// Removes a temporary capture session directory.
    func cleanupCaptureTemp(sessionId: String) {
        guard let baseDir = try? subdirectory(AppConstants.Storage.captureTempFolder) else { return }
        let sessionDir = baseDir.appendingPathComponent(sessionId, isDirectory: true)
        do {
            try FileManager.default.removeItem(at: sessionDir)
            logger.info("Cleaned up capture temp: \(sessionId)")
        } catch {
            logger.warning("Failed to cleanup capture temp \(sessionId): \(error.localizedDescription)")
        }
    }

    /// Removes all temporary capture session directories.
    func cleanupAllCaptureTemp() -> StorageCleanupSummary {
        guard let tempDir = try? subdirectory(AppConstants.Storage.captureTempFolder) else {
            return StorageCleanupSummary(deletedFiles: 0, reclaimedBytes: 0)
        }
        return removeContents(of: tempDir)
    }

    /// Deletes managed asset files that are no longer referenced by SwiftData metadata.
    func cleanupUnreferencedFiles(referencedFileNames: Set<String>) -> StorageCleanupSummary {
        let folders = [
            AppConstants.Storage.modelsFolder,
            AppConstants.Storage.thumbnailsFolder,
            AppConstants.Storage.photosFolder,
            AppConstants.Storage.voiceMemosFolder,
        ]

        var deletedFiles = 0
        var reclaimedBytes: Int64 = 0

        for folder in folders {
            guard let dir = try? subdirectory(folder),
                  let urls = try? FileManager.default.contentsOfDirectory(
                    at: dir,
                    includingPropertiesForKeys: [.fileSizeKey],
                    options: [.skipsHiddenFiles]
                  ) else {
                continue
            }

            for url in urls {
                let relativePath = "\(folder)/\(url.lastPathComponent)"
                guard !referencedFileNames.contains(relativePath) else { continue }

                let byteCount = fileSize(url: url)
                do {
                    try FileManager.default.removeItem(at: url)
                    deletedFiles += 1
                    reclaimedBytes += byteCount
                    logger.info("Deleted unreferenced file: \(relativePath)")
                } catch {
                    logger.warning("Failed to delete unreferenced file \(relativePath): \(error.localizedDescription)")
                }
            }
        }

        return StorageCleanupSummary(deletedFiles: deletedFiles, reclaimedBytes: reclaimedBytes)
    }

    // MARK: - Disk Space

    /// Returns available disk space in megabytes.
    func availableDiskSpaceMB() -> Int {
        do {
            let values = try URL(fileURLWithPath: NSHomeDirectory())
                .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            if let capacity = values.volumeAvailableCapacityForImportantUsage {
                return Int(capacity / (1024 * 1024))
            }
        } catch {
            logger.warning("Failed to check disk space: \(error.localizedDescription)")
        }
        return 0
    }

    /// Returns true if there's enough disk space for a capture session.
    var hasSufficientDiskSpace: Bool {
        availableDiskSpaceMB() >= AppConstants.Limits.minimumDiskSpaceMB
    }

    // MARK: - Setup

    /// Creates all required subdirectories. Called on app launch.
    func createDirectoryStructure() {
        do {
            _ = try modelsDirectory()
            _ = try thumbnailsDirectory()
            _ = try photosDirectory()
            _ = try voiceMemosDirectory()
            _ = try subdirectory(AppConstants.Storage.captureTempFolder)
            logger.info("Directory structure verified")
        } catch {
            logger.error("Failed to create directory structure: \(error.localizedDescription)")
        }
    }

    // MARK: - Private

    private func subdirectory(_ name: String) throws -> URL {
        let dir = try rootDirectory.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func removeContents(of directory: URL) -> StorageCleanupSummary {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return StorageCleanupSummary(deletedFiles: 0, reclaimedBytes: 0)
        }

        var deletedFiles = 0
        var reclaimedBytes: Int64 = 0

        for url in urls {
            let byteCount = recursiveSize(url: url)
            do {
                try FileManager.default.removeItem(at: url)
                deletedFiles += 1
                reclaimedBytes += byteCount
            } catch {
                logger.warning("Failed to remove temporary file \(url.lastPathComponent): \(error.localizedDescription)")
            }
        }

        return StorageCleanupSummary(deletedFiles: deletedFiles, reclaimedBytes: reclaimedBytes)
    }

    private func recursiveSize(url: URL) -> Int64 {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false), isDirectory: &isDirectory) else {
            return 0
        }

        if !isDirectory.boolValue {
            return fileSize(url: url)
        }

        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            total += fileSize(url: fileURL)
        }
        return total
    }

    private func fileSize(url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return Int64(values?.fileSize ?? 0)
    }
}

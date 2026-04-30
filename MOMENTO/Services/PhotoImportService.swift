import Foundation
import ImageIO
import os

/// Imports photos at original fidelity (no resize / no recompression).
nonisolated final class PhotoImportService: Sendable {

    static let shared = PhotoImportService()

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Momento", category: "PhotoImport")

    private init() {}

    // MARK: - Errors

    enum PhotoImportError: Error, LocalizedError {
        case invalidImageData
        case processingFailed

        var errorDescription: String? {
            switch self {
            case .invalidImageData: "The selected image could not be read."
            case .processingFailed: "Failed to process the image."
            }
        }
    }

    // MARK: - Public API

    /// Saves the original image bytes to the Photos directory.
    /// Returns the relative file name stored in SwiftData.
    @discardableResult
    func importPhoto(imageData: Data) throws -> String {
        let fileExtension = try inferredImageFileExtension(from: imageData)
        let fileName = try FileStorageService.shared.saveFile(
            data: imageData,
            directory: AppConstants.Storage.photosFolder,
            fileName: "\(UUID().uuidString).\(fileExtension)"
        )
        logger.info("Photo imported at original quality: \(fileName)")
        return fileName
    }

    private func inferredImageFileExtension(from imageData: Data) throws -> String {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let type = CGImageSourceGetType(source) as String? else {
            throw PhotoImportError.invalidImageData
        }

        switch type {
        case "public.heic":
            return "heic"
        case "public.heif":
            return "heif"
        case "public.png":
            return "png"
        case "public.tiff":
            return "tiff"
        case "com.compuserve.gif":
            return "gif"
        case "public.jpeg":
            fallthrough
        default:
            return "jpg"
        }
    }
}

import ImageIO
import Foundation
import os

/// Imports photos while removing location metadata before writing them to app storage.
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

    /// Saves image bytes to the Photos directory after stripping GPS/location metadata when possible.
    /// Returns the relative file name stored in SwiftData.
    @discardableResult
    func importPhoto(imageData: Data) throws -> String {
        let fileExtension = try inferredImageFileExtension(from: imageData)
        let sanitizedData = try sanitizedImageData(from: imageData)
        let fileName = try FileStorageService.shared.saveFile(
            data: sanitizedData,
            directory: AppConstants.Storage.photosFolder,
            fileName: "\(UUID().uuidString).\(fileExtension)"
        )
        logger.info("Photo imported with location metadata removed: \(fileName)")
        return fileName
    }

    /// Returns image data with GPS metadata removed. Exposed for focused tests.
    func sanitizedImageData(from imageData: Data) throws -> Data {
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let type = CGImageSourceGetType(source) else {
            throw PhotoImportError.invalidImageData
        }

        guard let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw PhotoImportError.processingFailed
        }

        let outputData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(outputData, type, 1, nil) else {
            throw PhotoImportError.processingFailed
        }

        let sourceProperties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        var sanitizedProperties = sourceProperties ?? [:]
        sanitizedProperties.removeValue(forKey: kCGImagePropertyGPSDictionary)

        CGImageDestinationAddImage(destination, cgImage, sanitizedProperties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw PhotoImportError.processingFailed
        }

        return outputData as Data
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

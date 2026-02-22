import CoreGraphics
import ImageIO
import UIKit
import UniformTypeIdentifiers
import os

/// Strips EXIF/GPS metadata from imported photos, resizes to a max dimension, and saves as JPEG.
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

    /// Strips metadata, resizes, compresses to JPEG, and saves to the Photos directory.
    /// Returns the relative file name stored in SwiftData.
    @discardableResult
    func importPhoto(imageData: Data) throws -> String {
        let processedData = try stripAndResize(imageData: imageData)
        let fileName = try FileStorageService.shared.saveFile(
            data: processedData,
            directory: AppConstants.Storage.photosFolder,
            fileName: "\(UUID().uuidString).jpg"
        )
        logger.info("Photo imported: \(fileName)")
        return fileName
    }

    /// Strips GPS/EXIF metadata and resizes to max dimension. Returns clean JPEG data.
    func stripAndResize(imageData: Data) throws -> Data {
        // Decode the image
        guard let source = CGImageSourceCreateWithData(imageData as CFData, nil),
              let cgImage = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw PhotoImportError.invalidImageData
        }

        // Resize if needed
        let resized = resize(cgImage, maxDimension: AppConstants.Photo.maxDimension)

        // Re-encode as JPEG without metadata (strips GPS, EXIF maker notes, XMP, etc.)
        let mutableData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            mutableData,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw PhotoImportError.processingFailed
        }

        // Only preserve orientation from the original; everything else is stripped
        var properties: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: AppConstants.Photo.compressionQuality
        ]

        if let sourceProperties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let orientation = sourceProperties[kCGImagePropertyOrientation] {
            properties[kCGImagePropertyOrientation] = orientation
        }

        CGImageDestinationAddImage(destination, resized, properties as CFDictionary)

        guard CGImageDestinationFinalize(destination) else {
            throw PhotoImportError.processingFailed
        }

        logger.info("Stripped metadata. Original \(cgImage.width)x\(cgImage.height) -> \(resized.width)x\(resized.height)")
        return mutableData as Data
    }

    // MARK: - Private

    /// Resizes a CGImage so its longest side is at most `maxDimension`. Uses Core Graphics (thread-safe).
    private func resize(_ cgImage: CGImage, maxDimension: CGFloat) -> CGImage {
        let width = CGFloat(cgImage.width)
        let height = CGFloat(cgImage.height)

        guard width > maxDimension || height > maxDimension else { return cgImage }

        let scale = min(maxDimension / width, maxDimension / height)
        let newWidth = Int(width * scale)
        let newHeight = Int(height * scale)

        let colorSpace = cgImage.colorSpace ?? CGColorSpaceCreateDeviceRGB()

        // Use a compatible bitmap info — force premultiplied alpha + skip handling
        let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)

        guard let context = CGContext(
            data: nil,
            width: newWidth,
            height: newHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: bitmapInfo.rawValue
        ) else {
            return cgImage
        }

        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: newWidth, height: newHeight))
        return context.makeImage() ?? cgImage
    }
}

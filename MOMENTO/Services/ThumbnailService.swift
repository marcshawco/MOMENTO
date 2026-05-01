import ImageIO
import QuickLookThumbnailing
import UIKit
import os

/// Generates lightweight thumbnails without loading freshly reconstructed USDZ files into SceneKit.
nonisolated final class ThumbnailService: Sendable {

    static let shared = ThumbnailService()

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Momento", category: "Thumbnail")

    private init() {}

    enum ThumbnailError: Error, LocalizedError {
        case noRepresentativeImage
        case imageDecodeFailed
        case quickLookFailed(String)
        case compressionFailed

        var errorDescription: String? {
            switch self {
            case .noRepresentativeImage: "No captured image was available for a thumbnail"
            case .imageDecodeFailed: "Failed to decode captured image for thumbnail"
            case .quickLookFailed(let message): "Failed to generate model preview: \(message)"
            case .compressionFailed: "Failed to encode thumbnail image"
            }
        }
    }

    /// Generates a PNG thumbnail from a representative capture photo.
    ///
    /// This is intentionally the preferred completion-path thumbnail. Loading the just-produced
    /// USDZ into a 3D renderer immediately after photogrammetry can trigger native rendering
    /// crashes on device before Swift error handling can recover.
    func generateCaptureThumbnail(
        from imagesDirectory: URL,
        size: CGFloat = AppConstants.Limits.thumbnailMaxDimension
    ) async throws -> Data {
        logger.info("Generating capture thumbnail from: \(imagesDirectory.lastPathComponent)")

        return try await Task.detached(priority: .utility) {
            guard let imageURL = try Self.representativeImageURL(in: imagesDirectory) else {
                throw ThumbnailError.noRepresentativeImage
            }

            guard let source = CGImageSourceCreateWithURL(imageURL as CFURL, nil) else {
                throw ThumbnailError.imageDecodeFailed
            }

            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: Int(size),
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: false,
            ]

            guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                throw ThumbnailError.imageDecodeFailed
            }

            let image = UIImage(cgImage: cgImage)
            guard let pngData = image.pngData() else {
                throw ThumbnailError.compressionFailed
            }

            return pngData
        }.value
    }

    /// Generates a PNG thumbnail from a USDZ file using Quick Look Thumbnailing.
    ///
    /// This is a safer fallback than SceneKit offscreen rendering because Quick Look owns the USDZ
    /// preview pipeline Apple uses across the system.
    func generateThumbnail(
        from usdzURL: URL,
        size: CGFloat = AppConstants.Limits.thumbnailMaxDimension
    ) async throws -> Data {
        logger.info("Generating Quick Look thumbnail from: \(usdzURL.lastPathComponent)")

        let scale = await MainActor.run { UIScreen.main.scale }
        let request = QLThumbnailGenerator.Request(
            fileAt: usdzURL,
            size: CGSize(width: size, height: size),
            scale: scale,
            representationTypes: .thumbnail
        )

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Data, Error>) in
            QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, error in
                if let image = representation?.uiImage,
                   let pngData = image.pngData() {
                    continuation.resume(returning: pngData)
                    return
                }

                if let error {
                    continuation.resume(throwing: ThumbnailError.quickLookFailed(error.localizedDescription))
                } else {
                    continuation.resume(throwing: ThumbnailError.quickLookFailed("No thumbnail representation was returned"))
                }
            }
        }
    }

    private static func representativeImageURL(in directory: URL) throws -> URL? {
        let allowedExtensions = Set(["jpg", "jpeg", "heic", "heif", "png"])
        let urls = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        .filter { allowedExtensions.contains($0.pathExtension.lowercased()) }
        .sorted { lhs, rhs in
            let lhsDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rhsDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return lhsDate < rhsDate
        }

        guard !urls.isEmpty else { return nil }
        return urls[urls.count / 2]
    }
}

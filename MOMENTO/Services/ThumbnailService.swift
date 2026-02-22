import SceneKit
import UIKit
import os

/// Generates thumbnail images from USDZ model files using SceneKit offscreen rendering.
nonisolated final class ThumbnailService: Sendable {

    static let shared = ThumbnailService()

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Momento", category: "Thumbnail")

    private init() {}

    enum ThumbnailError: Error, LocalizedError {
        case sceneLoadFailed
        case renderFailed
        case compressionFailed

        var errorDescription: String? {
            switch self {
            case .sceneLoadFailed: "Failed to load 3D model for thumbnail"
            case .renderFailed: "Failed to render thumbnail"
            case .compressionFailed: "Failed to compress thumbnail image"
            }
        }
    }

    /// Generates a JPEG thumbnail from a USDZ file. Must hop to MainActor for SceneKit rendering.
    func generateThumbnail(
        from usdzURL: URL,
        size: CGFloat = AppConstants.Limits.thumbnailMaxDimension
    ) async throws -> Data {
        logger.info("Generating thumbnail from: \(usdzURL.lastPathComponent)")

        // SceneKit rendering must happen on MainActor
        return try await MainActor.run {
            let scene: SCNScene
            do {
                scene = try SCNScene(url: usdzURL)
            } catch {
                throw ThumbnailError.sceneLoadFailed
            }

            let renderSize = CGSize(width: size, height: size)

            // Use SCNRenderer for offscreen rendering (no window hierarchy needed)
            let renderer = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
            renderer.scene = scene
            renderer.autoenablesDefaultLighting = true
            renderer.pointOfView = Self.createCamera(for: scene)

            let image = renderer.snapshot(atTime: 0, with: renderSize, antialiasingMode: .multisampling4X)

            guard let jpegData = image.jpegData(compressionQuality: AppConstants.Limits.thumbnailCompressionQuality) else {
                throw ThumbnailError.compressionFailed
            }

            return jpegData
        }
    }

    /// Creates a camera positioned to frame the scene's bounding box.
    @MainActor
    private static func createCamera(for scene: SCNScene) -> SCNNode {
        let (center, radius) = scene.rootNode.boundingSphere
        let cameraNode = SCNNode()
        cameraNode.camera = SCNCamera()
        cameraNode.camera?.automaticallyAdjustsZRange = true

        // Position camera to see the full object
        let distance = Float(radius) * 2.5
        cameraNode.position = SCNVector3(
            center.x + distance * 0.5,
            center.y + distance * 0.4,
            center.z + distance * 0.7
        )
        cameraNode.look(at: center)

        return cameraNode
    }
}

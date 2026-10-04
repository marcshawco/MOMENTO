import RealityKit
import SwiftUI

/// Single source of truth for which Momento capture paths the current device can run.
///
/// Momento has two independent hardware requirements and they are not the same check:
///
/// - Guided LiDAR capture needs `ObjectCaptureSession` (camera + LiDAR + a supported SoC).
/// - Photo Set Reconstruction only needs `PhotogrammetrySession`, which runs on more
///   devices because it consumes an existing image folder instead of driving the camera.
///
/// Everything else in the app (the shelf, metadata, photos, voice memos, notes, exports,
/// AR Quick Look) works on every device that can run iOS 26, so the shelf must never be
/// gated on these checks.
@MainActor
enum DeviceCapability {

    /// Whether Apple's guided Object Capture flow can run here.
    ///
    /// Authoritative runtime check — prefer this over any hardcoded model list.
    static var supportsGuidedObjectCapture: Bool {
        ObjectCaptureSession.isSupported
    }

    /// Whether on-device photogrammetry can turn an image folder into a USDZ here.
    ///
    /// Required by both capture paths: guided capture also reconstructs through
    /// `PhotogrammetrySession` once the scan pass finishes.
    static var supportsOnDeviceReconstruction: Bool {
        PhotogrammetrySession.isSupported
    }

    /// Whether the user can create any kind of 3D model on this device.
    static var supportsAnyCapturePath: Bool {
        supportsOnDeviceReconstruction
    }

    // MARK: - User-Facing Copy

    /// Explains why guided capture is unavailable, and what the user can do instead.
    static var guidedCaptureUnavailableMessage: String {
        if supportsOnDeviceReconstruction {
            return """
            Guided scanning needs a LiDAR-equipped iPhone or iPad (iPhone Pro models and \
            iPad Pro). This device can still build models from a photo set — use Photo Set \
            Reconstruction instead.
            """
        }

        return """
        This device cannot build 3D models on-device. A LiDAR-equipped iPhone Pro or iPad Pro \
        is recommended. You can still catalog items with photos, notes, voice memos, and exports.
        """
    }

    /// Explains why photo set reconstruction is unavailable.
    static var reconstructionUnavailableMessage: String {
        """
        On-device 3D reconstruction is not available on this device. You can still catalog items \
        with photos, notes, voice memos, valuations, and exports.
        """
    }

    /// Short recommendation shown alongside the capture mode picker.
    static var recommendedHardwareSummary: String {
        """
        Best results: iPhone 15 Pro or newer, or an iPad Pro with LiDAR. Guided scanning needs \
        LiDAR; photo set reconstruction does not.
        """
    }
}

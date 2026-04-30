import Foundation

enum CaptureGuidanceSeverity: String, Equatable {
    case critical
    case warning
    case info
    case success
}

struct CaptureGuidance: Equatable {
    let title: String
    let detail: String
    let severity: CaptureGuidanceSeverity
    let systemImage: String
}

enum CaptureGuidanceFlowState: Equatable {
    case idle
    case initializing
    case ready
    case detecting
    case capturing
    case finishing
    case completed
    case reconstructing
    case generatingThumbnail
    case saved
    case failed
    case unsupported
}

struct CaptureGuidanceSnapshot: Equatable {
    let flowState: CaptureGuidanceFlowState
    let trackingIsNormal: Bool
    let trackingDescription: String
    let canRequestImageCapture: Bool
    let shotCount: Int
    let shotStallSeconds: TimeInterval
    let coverage: Double
    let userCompletedScanPass: Bool
    let hasLowLightFeedback: Bool
    let hasMovingTooFastFeedback: Bool
    let hasTooCloseFeedback: Bool
    let hasTooFarFeedback: Bool
    let hasOutOfFieldOfViewFeedback: Bool
}

enum CaptureGuidanceEngine {

    static func guidance(for snapshot: CaptureGuidanceSnapshot) -> CaptureGuidance {
        if snapshot.userCompletedScanPass {
            return CaptureGuidance(
                title: "Ready to finish",
                detail: "Coverage looks good. Tap Finish Capture.",
                severity: .success,
                systemImage: "checkmark.circle.fill"
            )
        }

        if !snapshot.trackingIsNormal {
            return CaptureGuidance(
                title: "Stabilize tracking",
                detail: "\(snapshot.trackingDescription). Move slower and include textured background.",
                severity: .critical,
                systemImage: "viewfinder"
            )
        }

        if snapshot.flowState == .detecting && !snapshot.canRequestImageCapture {
            return CaptureGuidance(
                title: "Set bounding box",
                detail: "Adjust the box so the object sits inside and the base aligns with a stable surface.",
                severity: .critical,
                systemImage: "cube.transparent"
            )
        }

        if snapshot.hasLowLightFeedback {
            return CaptureGuidance(
                title: "Increase light",
                detail: "Add direct light or enable flashlight so the surface has stronger texture.",
                severity: .critical,
                systemImage: "sun.max.fill"
            )
        }

        if snapshot.hasMovingTooFastFeedback {
            return CaptureGuidance(
                title: "Move slower",
                detail: "Slow your orbit and keep object size steady in frame to improve shot quality.",
                severity: .warning,
                systemImage: "tortoise.fill"
            )
        }

        if snapshot.hasTooCloseFeedback {
            return CaptureGuidance(
                title: "Step back",
                detail: "Back up slightly so the full object and margin are visible.",
                severity: .warning,
                systemImage: "arrow.down.right.and.arrow.up.left"
            )
        }

        if snapshot.hasTooFarFeedback {
            return CaptureGuidance(
                title: "Move closer",
                detail: "Fill more of the frame with the object while keeping edges visible.",
                severity: .warning,
                systemImage: "arrow.up.left.and.arrow.down.right"
            )
        }

        if snapshot.hasOutOfFieldOfViewFeedback {
            return CaptureGuidance(
                title: "Re-center object",
                detail: "Keep the object centered before moving to the next angle.",
                severity: .warning,
                systemImage: "viewfinder"
            )
        }

        if snapshot.flowState == .capturing && snapshot.shotStallSeconds >= 8 {
            return CaptureGuidance(
                title: "No new usable shots",
                detail: "Change angle (top/back) and move slower to capture missing geometry.",
                severity: .warning,
                systemImage: "exclamationmark.triangle.fill"
            )
        }

        if snapshot.flowState == .capturing {
            if snapshot.coverage < 0.35 {
                return CaptureGuidance(
                    title: "Capture first ring",
                    detail: "Circle the object at one height and capture all sides.",
                    severity: .info,
                    systemImage: "arrow.triangle.2.circlepath"
                )
            }

            if snapshot.coverage < 0.75 {
                return CaptureGuidance(
                    title: "Capture second ring",
                    detail: "Add diagonal views and include top and side transitions.",
                    severity: .info,
                    systemImage: "rotate.3d"
                )
            }

            return CaptureGuidance(
                title: "Almost done",
                detail: "Add top/back edge detail to close remaining gaps.",
                severity: .info,
                systemImage: "sparkles"
            )
        }

        if snapshot.flowState == .ready {
            return CaptureGuidance(
                title: "Start scan",
                detail: "Tap Start Scanning and keep the object on a stable surface.",
                severity: .info,
                systemImage: "play.circle"
            )
        }

        if snapshot.flowState == .detecting {
            return CaptureGuidance(
                title: "Detecting object",
                detail: "Hold steady while the capture box settles, then continue around the object.",
                severity: .info,
                systemImage: "cube.transparent"
            )
        }

        return CaptureGuidance(
            title: "Continue scanning",
            detail: "Capture all sides with smooth movement and consistent distance.",
            severity: .info,
            systemImage: "camera.metering.center.weighted"
        )
    }
}

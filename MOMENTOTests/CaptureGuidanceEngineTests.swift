import XCTest
@testable import MOMENTO

final class CaptureGuidanceEngineTests: XCTestCase {

    func testLowLightReturnsCriticalGuidance() {
        let guidance = CaptureGuidanceEngine.guidance(for: snapshot(hasLowLightFeedback: true))

        XCTAssertEqual(guidance.severity, .critical)
        XCTAssertEqual(guidance.title, "Increase light")
    }

    func testStallReturnsNoNewUsableShotsGuidance() {
        let guidance = CaptureGuidanceEngine.guidance(
            for: snapshot(
                flowState: .capturing,
                shotCount: 24,
                shotStallSeconds: 8.2,
                coverage: 0.55
            )
        )

        XCTAssertEqual(guidance.severity, .warning)
        XCTAssertEqual(guidance.title, "No new usable shots")
    }

    func testCompletedScanPassReturnsReadyToFinish() {
        let guidance = CaptureGuidanceEngine.guidance(
            for: snapshot(
                flowState: .capturing,
                coverage: 0.9,
                userCompletedScanPass: true
            )
        )

        XCTAssertEqual(guidance.severity, .success)
        XCTAssertEqual(guidance.title, "Ready to finish")
    }

    func testCriticalBlockerWinsOverPhaseHint() {
        let guidance = CaptureGuidanceEngine.guidance(
            for: snapshot(
                flowState: .capturing,
                trackingIsNormal: false,
                trackingDescription: "Tracking limited",
                coverage: 0.8,
                hasMovingTooFastFeedback: true
            )
        )

        XCTAssertEqual(guidance.severity, .critical)
        XCTAssertEqual(guidance.title, "Stabilize tracking")
    }

    func testCaptureSetQualityAcceptsStrongImageSet() {
        let report = CaptureSetQualityService.evaluate(
            metrics: CaptureSetQualityMetrics(
                totalImages: 42,
                analyzedImages: 42,
                usableImages: 38,
                averageBrightness: 0.5,
                averageSharpness: 0.04
            )
        )

        XCTAssertTrue(report.isReconstructionReady)
        XCTAssertTrue(report.issues.isEmpty)
    }

    func testCaptureSetQualityRejectsWeakImageSetBeforeReconstruction() {
        let report = CaptureSetQualityService.evaluate(
            metrics: CaptureSetQualityMetrics(
                totalImages: 12,
                analyzedImages: 12,
                usableImages: 5,
                averageBrightness: 0.08,
                averageSharpness: 0.006
            )
        )

        XCTAssertFalse(report.isReconstructionReady)
        XCTAssertTrue(report.issues.contains(.tooFewImages))
        XCTAssertTrue(report.issues.contains(.tooFewUsableImages))
        XCTAssertTrue(report.issues.contains(.tooDark))
        XCTAssertTrue(report.issues.contains(.tooSoft))
    }

    func testCaptureSetQualityFlagsLowUsableRatio() {
        let report = CaptureSetQualityService.evaluate(
            metrics: CaptureSetQualityMetrics(
                totalImages: 60,
                analyzedImages: 60,
                usableImages: 24,
                averageBrightness: 0.45,
                averageSharpness: 0.04
            )
        )

        XCTAssertFalse(report.isReconstructionReady)
        XCTAssertTrue(report.issues.contains(.tooFewUsableImages))
    }

    func testUnsupportedCaptureStateReturnsUnsupportedGuidance() {
        let guidance = CaptureGuidanceEngine.guidance(
            for: snapshot(flowState: .unsupported)
        )

        XCTAssertEqual(guidance.severity, .critical)
        XCTAssertEqual(guidance.title, "Unsupported device")
    }

    private func snapshot(
        flowState: CaptureGuidanceFlowState = .capturing,
        trackingIsNormal: Bool = true,
        trackingDescription: String = "Plane locked",
        canRequestImageCapture: Bool = true,
        shotCount: Int = 10,
        shotStallSeconds: TimeInterval = 0,
        coverage: Double = 0.4,
        userCompletedScanPass: Bool = false,
        hasLowLightFeedback: Bool = false,
        hasMovingTooFastFeedback: Bool = false,
        hasTooCloseFeedback: Bool = false,
        hasTooFarFeedback: Bool = false,
        hasOutOfFieldOfViewFeedback: Bool = false
    ) -> CaptureGuidanceSnapshot {
        CaptureGuidanceSnapshot(
            flowState: flowState,
            trackingIsNormal: trackingIsNormal,
            trackingDescription: trackingDescription,
            canRequestImageCapture: canRequestImageCapture,
            shotCount: shotCount,
            shotStallSeconds: shotStallSeconds,
            coverage: coverage,
            userCompletedScanPass: userCompletedScanPass,
            hasLowLightFeedback: hasLowLightFeedback,
            hasMovingTooFastFeedback: hasMovingTooFastFeedback,
            hasTooCloseFeedback: hasTooCloseFeedback,
            hasTooFarFeedback: hasTooFarFeedback,
            hasOutOfFieldOfViewFeedback: hasOutOfFieldOfViewFeedback
        )
    }
}

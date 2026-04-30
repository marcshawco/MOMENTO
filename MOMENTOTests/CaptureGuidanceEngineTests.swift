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

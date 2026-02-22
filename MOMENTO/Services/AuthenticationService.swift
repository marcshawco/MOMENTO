import LocalAuthentication
import os

/// Manages biometric (FaceID/TouchID) authentication state.
/// MainActor-isolated (default) since it drives UI state directly.
@Observable
final class AuthenticationService {

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Momento", category: "Auth")

    // MARK: - Observable State

    /// Whether the user has successfully authenticated this session.
    var isUnlocked = false

    /// Error message from the last failed authentication attempt.
    var authError: String?

    /// Whether biometric authentication is available on this device.
    var isBiometricAvailable: Bool {
        let context = LAContext()
        var error: NSError?
        return context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
    }

    // MARK: - Authentication

    /// Triggers biometric authentication. Sets `isUnlocked` on success.
    func authenticate() async {
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"

        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) else {
            // Biometric not available (Simulator, no FaceID, etc.) — auto-unlock
            logger.info("Biometric unavailable, auto-unlocking: \(error?.localizedDescription ?? "unknown")")
            isUnlocked = true
            authError = nil
            return
        }

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthenticationWithBiometrics,
                localizedReason: "Unlock your Momento collection"
            )

            if success {
                isUnlocked = true
                authError = nil
                logger.info("Biometric authentication succeeded")
            }
        } catch {
            authError = error.localizedDescription
            logger.warning("Biometric authentication failed: \(error.localizedDescription)")
        }
    }

    /// Locks the app (called when entering background).
    func lock() {
        isUnlocked = false
        authError = nil
        logger.info("App locked")
    }
}

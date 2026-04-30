import LocalAuthentication
import os

/// Manages biometric (FaceID/TouchID) authentication state.
/// MainActor-isolated (default) since it drives UI state directly.
@MainActor
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

    /// Verifies biometric auth before enabling the app lock setting.
    func verifyBiometricBeforeEnabling() async -> Bool {
        guard isBiometricAvailable else {
            isUnlocked = false
            authError = "Face ID is not available on this device or has not been configured."
            return false
        }

        await authenticate()
        return isUnlocked
    }

    /// Triggers biometric authentication. Sets `isUnlocked` on success.
    func authenticate() async {
        let context = LAContext()
        context.localizedCancelTitle = "Cancel"

        var error: NSError?
        let policy: LAPolicy = .deviceOwnerAuthentication

        guard context.canEvaluatePolicy(policy, error: &error) else {
            // Keep app locked if authentication cannot be evaluated.
            isUnlocked = false
            authError = "Device authentication is unavailable."
            logger.warning("Authentication unavailable: \(error?.localizedDescription ?? "unknown")")
            return
        }

        do {
            let success = try await context.evaluatePolicy(
                policy,
                localizedReason: "Unlock your Momento collection"
            )

            if success {
                isUnlocked = true
                authError = nil
                logger.info("Authentication succeeded")
            }
        } catch {
            isUnlocked = false
            authError = error.localizedDescription
            logger.warning("Authentication failed: \(error.localizedDescription)")
        }
    }

    /// Locks the app (called when entering background).
    func lock() {
        isUnlocked = false
        authError = nil
        logger.info("App locked")
    }
}

import AVFoundation
import Photos
import UIKit
import os

@MainActor
@Observable
final class PermissionService {

    enum PermissionStatus {
        case notDetermined
        case authorized
        case denied
        case restricted

        var label: String {
            switch self {
            case .notDetermined:
                "Not Requested"
            case .authorized:
                "Allowed"
            case .denied:
                "Denied"
            case .restricted:
                "Restricted"
            }
        }

        var symbolName: String {
            switch self {
            case .notDetermined:
                "questionmark.circle"
            case .authorized:
                "checkmark.circle.fill"
            case .denied:
                "xmark.circle.fill"
            case .restricted:
                "exclamationmark.triangle.fill"
            }
        }
    }

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "Momento",
        category: "Permissions"
    )

    var cameraStatus: PermissionStatus = .notDetermined
    var microphoneStatus: PermissionStatus = .notDetermined
    var photoLibraryStatus: PermissionStatus = .notDetermined

    var allRequiredGranted: Bool {
        cameraStatus == .authorized
            && microphoneStatus == .authorized
            && photoLibraryStatus == .authorized
    }

    func refreshStatuses() {
        cameraStatus = mapCamera(AVCaptureDevice.authorizationStatus(for: .video))
        microphoneStatus = mapMicrophone(AVAudioApplication.shared.recordPermission)
        photoLibraryStatus = mapPhotoLibrary(PHPhotoLibrary.authorizationStatus(for: .readWrite))
    }

    func requestMissingPermissions() async {
        if cameraStatus == .notDetermined {
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            logger.info("Camera permission requested: \(granted)")
        }

        if microphoneStatus == .notDetermined {
            let granted = await requestMicrophoneAccess()
            logger.info("Microphone permission requested: \(granted)")
        }

        if photoLibraryStatus == .notDetermined {
            let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            logger.info("Photo permission requested: \(String(describing: status.rawValue))")
        }

        refreshStatuses()
    }

    func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func requestMicrophoneAccess() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    private func mapCamera(_ status: AVAuthorizationStatus) -> PermissionStatus {
        switch status {
        case .notDetermined:
            .notDetermined
        case .authorized:
            .authorized
        case .denied:
            .denied
        case .restricted:
            .restricted
        @unknown default:
            .restricted
        }
    }

    private func mapMicrophone(_ status: AVAudioApplication.recordPermission) -> PermissionStatus {
        switch status {
        case .undetermined:
            .notDetermined
        case .granted:
            .authorized
        case .denied:
            .denied
        @unknown default:
            .restricted
        }
    }

    private func mapPhotoLibrary(_ status: PHAuthorizationStatus) -> PermissionStatus {
        switch status {
        case .notDetermined:
            .notDetermined
        case .authorized, .limited:
            .authorized
        case .denied:
            .denied
        case .restricted:
            .restricted
        @unknown default:
            .restricted
        }
    }
}

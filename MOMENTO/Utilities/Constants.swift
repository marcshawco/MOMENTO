import Foundation

enum AppConstants {
    // MARK: - File Storage Directories
    enum Storage {
        static let rootFolder = "Momento"
        static let modelsFolder = "Models"
        static let thumbnailsFolder = "Thumbnails"
        static let photosFolder = "Photos"
        static let voiceMemosFolder = "VoiceMemos"
        static let captureTempFolder = "CaptureTemp"
    }

    // MARK: - Limits
    enum Limits {
        static let minimumDiskSpaceMB: Int = 500
        static let thumbnailMaxDimension: CGFloat = 512
        static let thumbnailCompressionQuality: CGFloat = 0.8
        static let gridItemMinWidth: CGFloat = 160
        static let gridSpacing: CGFloat = 16
    }

    // MARK: - UserDefaults Keys
    enum UserDefaultsKeys {
        static let hasSeenOnboarding = "hasSeenOnboarding"
        static let isFaceIDEnabled = "isFaceIDEnabled"
        static let preferredSortOrder = "preferredSortOrder"
    }
}

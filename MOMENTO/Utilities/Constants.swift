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

    // MARK: - Photo Import
    enum Photo {
        static let maxDimension: CGFloat = 2048
        static let compressionQuality: CGFloat = 0.85
    }

    // MARK: - Audio Recording
    enum Audio {
        static let sampleRate: Double = 44100
        static let numberOfChannels: Int = 1
        static let bitRate: Int = 128_000
        static let fileExtension = "m4a"
    }

    // MARK: - Detail View
    enum Detail {
        static let autoSaveDebounce: TimeInterval = 0.8
        static let modelPreviewHeight: CGFloat = 300
    }

    // MARK: - UserDefaults Keys
    enum UserDefaultsKeys {
        static let hasSeenOnboarding = "hasSeenOnboarding"
        static let isFaceIDEnabled = "isFaceIDEnabled"
        static let preferredSortOrder = "preferredSortOrder"
    }
}

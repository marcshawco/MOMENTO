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

    // MARK: - Export
    enum Export {
        static let pageWidth: CGFloat = 612   // US Letter
        static let pageHeight: CGFloat = 792
        static let margin: CGFloat = 50
        static let thumbnailMaxSize: CGFloat = 200
        static let titleFontSize: CGFloat = 24
        static let headingFontSize: CGFloat = 16
        static let bodyFontSize: CGFloat = 12
        static let captionFontSize: CGFloat = 10
        static let lineSpacing: CGFloat = 6
        static let sectionSpacing: CGFloat = 20
        static let exportTempFolder = "Exports"
    }

    // MARK: - UserDefaults Keys
    enum UserDefaultsKeys {
        static let hasSeenOnboarding = "hasSeenOnboarding"
        static let isFaceIDEnabled = "isFaceIDEnabled"
        static let preferredSortOrder = "preferredSortOrder"
    }
}

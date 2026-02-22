import Foundation
import SwiftData

@Model
final class VoiceMemo {
    #Unique<VoiceMemo>([\.id])

    var id: UUID
    var fileName: String
    var duration: TimeInterval
    var createdAt: Date
    var transcriptPlaceholder: String?

    var item: CollectionItem?

    init(
        id: UUID = UUID(),
        fileName: String,
        duration: TimeInterval = 0,
        createdAt: Date = .now,
        transcriptPlaceholder: String? = nil,
        item: CollectionItem? = nil
    ) {
        self.id = id
        self.fileName = fileName
        self.duration = duration
        self.createdAt = createdAt
        self.transcriptPlaceholder = transcriptPlaceholder
        self.item = item
    }
}

extension VoiceMemo {
    var formattedDuration: String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

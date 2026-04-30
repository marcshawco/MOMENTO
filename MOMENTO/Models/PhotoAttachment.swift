import Foundation
import SwiftData

@Model
final class PhotoAttachment {
    @Attribute(.unique)
    var id: UUID
    var fileName: String
    var caption: String
    var createdAt: Date

    var item: CollectionItem?

    init(
        id: UUID = UUID(),
        fileName: String,
        caption: String = "",
        createdAt: Date = .now,
        item: CollectionItem? = nil
    ) {
        self.id = id
        self.fileName = fileName
        self.caption = caption
        self.createdAt = createdAt
        self.item = item
    }
}

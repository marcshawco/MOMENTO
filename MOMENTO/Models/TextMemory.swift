import Foundation
import SwiftData

@Model
final class TextMemory {
    @Attribute(.unique)
    var id: UUID
    var body: String
    var createdAt: Date

    var item: CollectionItem?

    init(
        id: UUID = UUID(),
        body: String = "",
        createdAt: Date = .now,
        item: CollectionItem? = nil
    ) {
        self.id = id
        self.body = body
        self.createdAt = createdAt
        self.item = item
    }
}

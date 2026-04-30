import Foundation
import SwiftData

@Model
final class CollectionItem {
    @Attribute(.unique)
    var id: UUID
    var title: String
    var itemDescription: String
    var createdAt: Date
    var updatedAt: Date
    @Attribute(.transformable(by: StringArrayValueTransformer.self))
    var tags: [String]
    var collectionName: String

    // Purchase & valuation
    var purchaseDate: Date?
    var purchasePrice: Double?
    var estimatedValue: Double?
    var serialNumber: String?
    var provenanceNotes: String?

    // File references (relative paths resolved by FileStorageService)
    var modelFileName: String?
    var thumbnailFileName: String?

    // Relationships
    @Relationship(deleteRule: .cascade, inverse: \PhotoAttachment.item)
    var photoAttachments: [PhotoAttachment]

    @Relationship(deleteRule: .cascade, inverse: \VoiceMemo.item)
    var voiceMemos: [VoiceMemo]

    @Relationship(deleteRule: .cascade, inverse: \TextMemory.item)
    var textMemories: [TextMemory]

    // Pro feature stubs (not used in MVP)
    var cloudSyncIdentifier: String?
    var provenanceManifestData: Data?

    init(
        id: UUID = UUID(),
        title: String = "",
        itemDescription: String = "",
        createdAt: Date = .now,
        updatedAt: Date = .now,
        tags: [String] = [],
        collectionName: String = "",
        purchaseDate: Date? = nil,
        purchasePrice: Double? = nil,
        estimatedValue: Double? = nil,
        serialNumber: String? = nil,
        provenanceNotes: String? = nil,
        modelFileName: String? = nil,
        thumbnailFileName: String? = nil
    ) {
        self.id = id
        self.title = title
        self.itemDescription = itemDescription
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.tags = tags
        self.collectionName = collectionName
        self.purchaseDate = purchaseDate
        self.purchasePrice = purchasePrice
        self.estimatedValue = estimatedValue
        self.serialNumber = serialNumber
        self.provenanceNotes = provenanceNotes
        self.modelFileName = modelFileName
        self.thumbnailFileName = thumbnailFileName
        self.photoAttachments = []
        self.voiceMemos = []
        self.textMemories = []
    }
}

extension CollectionItem {
    var formattedEstimatedValue: String? {
        guard let estimatedValue else { return nil }
        return estimatedValue.formatted(.currency(code: "USD"))
    }

    var formattedPurchasePrice: String? {
        guard let purchasePrice else { return nil }
        return purchasePrice.formatted(.currency(code: "USD"))
    }

    func touch() {
        updatedAt = .now
    }
}

import Foundation
import SwiftData

@MainActor
enum SampleData {

    /// In-memory ModelContainer for SwiftUI previews. Prepopulated with sample items.
    static var previewContainer: ModelContainer? {
        let schema = Schema([
            CollectionItem.self,
            PhotoAttachment.self,
            VoiceMemo.self,
            TextMemory.self,
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)

        do {
            let container = try ModelContainer(for: schema, configurations: [config])
            let context = container.mainContext

            // Insert sample items
            for item in sampleItems {
                context.insert(item)
            }

            return container
        } catch {
            assertionFailure("Failed to create preview container: \(error)")
            return nil
        }
    }

    // MARK: - Individual Samples

    static var sampleItem: CollectionItem {
        CollectionItem(
            title: "Vintage Leica M3",
            itemDescription: "1957 Leica M3 double-stroke rangefinder camera in excellent condition. Original leather case included.",
            tags: ["camera", "vintage", "leica"],
            collectionName: "Cameras",
            purchaseDate: Calendar.current.date(from: DateComponents(year: 2023, month: 6, day: 15)),
            purchasePrice: 1800,
            estimatedValue: 2400,
            serialNumber: "M3-854921",
            provenanceNotes: "Purchased from estate sale in Portland, OR."
        )
    }

    static var sampleItemNoThumbnail: CollectionItem {
        CollectionItem(
            title: "First Edition Book",
            itemDescription: "Signed first edition.",
            tags: ["book", "rare"],
            collectionName: "Books",
            estimatedValue: 350
        )
    }

    /// Sample item pre-configured with attachments for detail view previews.
    static var sampleItemWithAttachments: CollectionItem {
        let item = CollectionItem(
            title: "Vintage Leica M3",
            itemDescription: "1957 Leica M3 double-stroke rangefinder camera in excellent condition. Original leather case included.",
            tags: ["camera", "vintage", "leica", "german"],
            collectionName: "Cameras",
            purchaseDate: Calendar.current.date(from: DateComponents(year: 2023, month: 6, day: 15)),
            purchasePrice: 1800,
            estimatedValue: 2400,
            serialNumber: "M3-854921",
            provenanceNotes: "Purchased from estate sale in Portland, OR. Previous owner was a photojournalist."
        )

        // Simulate attachments (file names won't resolve to real files in previews, but models are populated)
        let photo1 = PhotoAttachment(fileName: "Photos/leica-front.jpg", caption: "Front view", item: item)
        let photo2 = PhotoAttachment(fileName: "Photos/leica-back.jpg", caption: "Rear view", item: item)
        item.photoAttachments = [photo1, photo2]

        let memo = VoiceMemo(fileName: "VoiceMemos/leica-notes.m4a", duration: 42, item: item)
        item.voiceMemos = [memo]

        let note1 = TextMemory(body: "Shutter speeds all accurate. Light meter needs CLA.", item: item)
        let note2 = TextMemory(body: "Comparable units selling for $2,200–$2,600 on eBay.", item: item)
        item.textMemories = [note1, note2]

        return item
    }

    // MARK: - Batch Samples

    static var sampleItems: [CollectionItem] {
        [
            CollectionItem(
                title: "Vintage Leica M3",
                itemDescription: "1957 Leica M3 double-stroke rangefinder camera in excellent condition.",
                tags: ["camera", "vintage", "leica"],
                collectionName: "Cameras",
                purchasePrice: 1800,
                estimatedValue: 2400,
                serialNumber: "M3-854921"
            ),
            CollectionItem(
                title: "Omega Speedmaster",
                itemDescription: "1969 Omega Speedmaster Professional, cal. 861. Box and papers.",
                tags: ["watch", "omega", "vintage"],
                collectionName: "Watches",
                purchasePrice: 5200,
                estimatedValue: 7500,
                serialNumber: "SP-291048"
            ),
            CollectionItem(
                title: "Gibson Les Paul Standard",
                itemDescription: "1959 reissue in Heritage Cherry Sunburst. Light play wear.",
                tags: ["guitar", "gibson", "instrument"],
                collectionName: "Instruments",
                purchasePrice: 3800,
                estimatedValue: 4200
            ),
            CollectionItem(
                title: "Roman Denarius",
                itemDescription: "Silver denarius of Emperor Trajan, circa 110 AD. VF condition.",
                tags: ["coin", "ancient", "silver"],
                collectionName: "Coins",
                estimatedValue: 450
            ),
            CollectionItem(
                title: "Art Deco Vase",
                itemDescription: "Roseville Pottery Futura vase, 1928. No chips or repairs.",
                tags: ["pottery", "art-deco", "roseville"],
                collectionName: "Ceramics",
                purchasePrice: 600,
                estimatedValue: 900
            ),
            CollectionItem(
                title: "Star Wars Figure",
                itemDescription: "Kenner Boba Fett action figure, 1979. Unpunched card.",
                tags: ["toy", "star-wars", "vintage"],
                collectionName: "Toys",
                estimatedValue: 1200
            ),
        ]
    }
}

import SwiftUI
import SwiftData

@main
struct MOMENTOApp: App {
    let modelContainer: ModelContainer

    init() {
        let schema = Schema([
            CollectionItem.self,
            PhotoAttachment.self,
            VoiceMemo.self,
            TextMemory.self,
        ])

        do {
            modelContainer = try ModelContainer(for: schema)
        } catch {
            fatalError("Failed to initialize ModelContainer: \(error)")
        }

        // Ensure file storage directories exist on launch
        FileStorageService.shared.createDirectoryStructure()
    }

    var body: some Scene {
        WindowGroup {
            ShelfView()
        }
        .modelContainer(modelContainer)
    }
}

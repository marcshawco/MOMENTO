import SwiftUI
import SwiftData

@main
struct MOMENTOApp: App {
    let modelContainer: ModelContainer

    @State private var authService = AuthenticationService()
    @AppStorage(AppConstants.UserDefaultsKeys.hasSeenOnboarding) private var hasSeenOnboarding = false
    @AppStorage(AppConstants.UserDefaultsKeys.isFaceIDEnabled) private var isFaceIDEnabled = false
    @Environment(\.scenePhase) private var scenePhase
    private let tagsNormalizationDefaultsKey = "momento.tagsNormalization.v1.completed"

    init() {
        StringArrayValueTransformer.register()

        let schema = Schema([
            CollectionItem.self,
            PhotoAttachment.self,
            VoiceMemo.self,
            TextMemory.self,
        ])

        do {
            modelContainer = try ModelContainer(for: schema)
            normalizeTagsIfNeeded()
        } catch {
            fatalError("Failed to initialize ModelContainer: \(error)")
        }

        // Ensure file storage directories exist on launch
        FileStorageService.shared.createDirectoryStructure()
    }

    var body: some Scene {
        WindowGroup {
            ShelfView()
                .overlay {
                    if isFaceIDEnabled && !authService.isUnlocked {
                        LockScreenView(authService: authService)
                    }
                }
                .fullScreenCover(isPresented: showOnboarding) {
                    OnboardingView()
                }
                .onChange(of: scenePhase) {
                    if scenePhase == .background && isFaceIDEnabled {
                        authService.lock()
                    }
                }
                .onAppear {
                    // Auto-unlock if FaceID is not enabled
                    if !isFaceIDEnabled {
                        authService.isUnlocked = true
                    }
                }
        }
        .modelContainer(modelContainer)
    }

    // MARK: - Helpers

    /// Binding that presents onboarding only on first launch.
    private var showOnboarding: Binding<Bool> {
        Binding(
            get: { !hasSeenOnboarding },
            set: { newValue in
                if !newValue {
                    hasSeenOnboarding = true
                }
            }
        )
    }

    private func normalizeTagsIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: tagsNormalizationDefaultsKey) else { return }

        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<CollectionItem>()

        do {
            let items = try context.fetch(descriptor)
            var hasChanges = false

            for item in items {
                let normalized = normalizedTags(item.tags)
                if normalized != item.tags {
                    item.tags = normalized
                    item.touch()
                    hasChanges = true
                }
            }

            if hasChanges {
                try context.save()
            }

            defaults.set(true, forKey: tagsNormalizationDefaultsKey)
        } catch {
            // Keep running if normalization fails; it can run again next launch.
        }
    }

    private func normalizedTags(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        var normalized: [String] = []

        for tag in tags {
            let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            let dedupeKey = trimmed.lowercased()
            if seen.insert(dedupeKey).inserted {
                normalized.append(trimmed)
            }
        }

        return normalized
    }
}

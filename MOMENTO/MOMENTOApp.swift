import SwiftUI
import SwiftData

@main
struct MOMENTOApp: App {
    private let startupResult: StartupResult

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
            let configuration = ModelConfiguration(schema: schema)
            let modelContainer = try ModelContainer(for: schema, configurations: [configuration])
            startupResult = .ready(modelContainer)
            Self.normalizeTagsIfNeeded(modelContainer: modelContainer, defaultsKey: tagsNormalizationDefaultsKey)
        } catch {
            startupResult = .failed("Momento could not open its private database. Restart the app, then check available device storage if this continues. Details: \(error.localizedDescription)")
        }

        // Ensure file storage directories exist on launch
        FileStorageService.shared.createDirectoryStructure()
    }

    var body: some Scene {
        WindowGroup {
            switch startupResult {
            case .ready(let modelContainer):
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
                    .modelContainer(modelContainer)

            case .failed(let message):
                StartupFailureView(message: message)
            }
        }
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

    private static func normalizeTagsIfNeeded(modelContainer: ModelContainer, defaultsKey: String) {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: defaultsKey) else { return }

        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<CollectionItem>()

        do {
            let items = try context.fetch(descriptor)
            var hasChanges = false

            for item in items {
                let normalized = Self.normalizedTags(item.tags)
                if normalized != item.tags {
                    item.tags = normalized
                    item.touch()
                    hasChanges = true
                }
            }

            if hasChanges {
                try context.save()
            }

            defaults.set(true, forKey: defaultsKey)
        } catch {
            // Keep running if normalization fails; it can run again next launch.
        }
    }

    private static func normalizedTags(_ tags: [String]) -> [String] {
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

private enum StartupResult {
    case ready(ModelContainer)
    case failed(String)
}

private struct StartupFailureView: View {
    let message: String

    var body: some View {
        ContentUnavailableView {
            Label("Storage Unavailable", systemImage: "externaldrive.badge.exclamationmark")
        } description: {
            Text(message)
        } actions: {
            Button("Open Settings") {
                guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                UIApplication.shared.open(url)
            }
        }
        .padding()
    }
}

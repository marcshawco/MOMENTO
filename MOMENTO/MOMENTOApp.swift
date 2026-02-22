import SwiftUI
import SwiftData

@main
struct MOMENTOApp: App {
    let modelContainer: ModelContainer

    @State private var authService = AuthenticationService()
    @AppStorage(AppConstants.UserDefaultsKeys.hasSeenOnboarding) private var hasSeenOnboarding = false
    @AppStorage(AppConstants.UserDefaultsKeys.isFaceIDEnabled) private var isFaceIDEnabled = false
    @Environment(\.scenePhase) private var scenePhase

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
}

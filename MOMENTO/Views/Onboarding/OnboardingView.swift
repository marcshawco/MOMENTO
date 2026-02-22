import SwiftUI

/// Three-page onboarding flow shown on first launch.
/// Sets `hasSeenOnboarding` in UserDefaults on completion.
struct OnboardingView: View {

    @AppStorage(AppConstants.UserDefaultsKeys.hasSeenOnboarding) private var hasSeenOnboarding = false
    @AppStorage(AppConstants.UserDefaultsKeys.isFaceIDEnabled) private var isFaceIDEnabled = false
    @Environment(\.dismiss) private var dismiss

    @State private var currentPage = 0

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $currentPage) {
                // Page 1: Welcome
                OnboardingPageView(
                    systemImage: "cube.transparent.fill",
                    imageColor: .accentColor,
                    title: "Welcome to Momento",
                    subtitle: "Create stunning 3D digital twins of your most prized collectibles, right from your iPhone."
                )
                .tag(0)

                // Page 2: Features
                OnboardingPageView(
                    systemImage: "camera.viewfinder",
                    imageColor: .orange,
                    title: "Scan, Catalog, Preserve",
                    subtitle: "Use your camera to capture 3D models, organize by collection, attach photos, voice memos, and notes."
                )
                .tag(1)

                // Page 3: Security
                securityPage
                    .tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            // Bottom button
            bottomButton
                .padding(.horizontal, 32)
                .padding(.bottom, 40)
        }
    }

    // MARK: - Security Page

    private var securityPage: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "faceid")
                .font(.system(size: 80))
                .foregroundStyle(.green)
                .symbolRenderingMode(.hierarchical)

            VStack(spacing: 12) {
                Text("Protect Your Collection")
                    .font(.title.weight(.bold))
                    .multilineTextAlignment(.center)

                Text("Enable Face ID to keep your collection private. You can change this later in Settings.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Toggle(isOn: $isFaceIDEnabled) {
                Label("Enable Face ID", systemImage: "faceid")
                    .font(.headline)
            }
            .toggleStyle(.switch)
            .padding(.horizontal, 48)
            .padding(.top, 8)

            Spacer()
            Spacer()
        }
        .padding()
    }

    // MARK: - Bottom Button

    private var bottomButton: some View {
        Button {
            if currentPage < 2 {
                withAnimation {
                    currentPage += 1
                }
            } else {
                completeOnboarding()
            }
        } label: {
            Text(currentPage < 2 ? "Continue" : "Get Started")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    // MARK: - Actions

    private func completeOnboarding() {
        hasSeenOnboarding = true
        dismiss()
    }
}

#Preview {
    OnboardingView()
}

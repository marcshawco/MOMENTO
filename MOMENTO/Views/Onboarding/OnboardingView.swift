import SwiftUI

/// Five-page onboarding flow shown on first launch.
/// Sets `hasSeenOnboarding` in UserDefaults on completion.
struct OnboardingView: View {

    @AppStorage(AppConstants.UserDefaultsKeys.hasSeenOnboarding) private var hasSeenOnboarding = false
    @AppStorage(AppConstants.UserDefaultsKeys.isFaceIDEnabled) private var isFaceIDEnabled = false
    @Environment(\.dismiss) private var dismiss

    @State private var currentPage = 0
    @State private var permissionService = PermissionService()
    @State private var authService = AuthenticationService()
    @State private var isRequestingPermissions = false
    @State private var securityMessage: String?

    private let pageCount = 5

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $currentPage) {
                // Page 1: Privacy-first intro
                OnboardingPageView(
                    systemImage: "lock.shield.fill",
                    imageColor: .blue,
                    title: "Welcome to Momento",
                    subtitle: "Create private 3D digital twins of physical collectibles and keep their stories in one scrapbook-like archive.",
                    highlights: [
                        OnboardingHighlight(
                            icon: "cube.transparent",
                            title: "3D digital twins",
                            detail: "Guided Object Capture creates USDZ models on supported devices."
                        ),
                        OnboardingHighlight(
                            icon: "lock",
                            title: "Local-first by default",
                            detail: "Your models, photos, notes, and voice memos stay on this device."
                        )
                    ]
                )
                .tag(0)

                // Page 2: Scanning guidance
                OnboardingPageView(
                    systemImage: "camera.viewfinder",
                    imageColor: .orange,
                    title: "Scan Better Models",
                    subtitle: "Good capture habits make sharper reconstructions and fewer failed scans.",
                    highlights: [
                        OnboardingHighlight(
                            icon: "lightbulb.max",
                            title: "Use soft, even light",
                            detail: "Avoid harsh shadows, glare, and bright backlight."
                        ),
                        OnboardingHighlight(
                            icon: "arrow.triangle.2.circlepath.camera",
                            title: "Move slowly around the object",
                            detail: "Keep the collectible stable and capture every side."
                        ),
                        OnboardingHighlight(
                            icon: "exclamationmark.triangle",
                            title: "Weak scans are caught early",
                            detail: "Momento checks image quality before reconstruction starts."
                        )
                    ]
                )
                .tag(1)

                // Page 3: Scrapbook archive
                OnboardingPageView(
                    systemImage: "books.vertical.fill",
                    imageColor: .purple,
                    title: "Build the Story",
                    subtitle: "Each item can hold the details collectors care about after the scan.",
                    highlights: [
                        OnboardingHighlight(
                            icon: "photo.on.rectangle",
                            title: "Photos and thumbnails",
                            detail: "Attach supporting photos while avoiding location metadata."
                        ),
                        OnboardingHighlight(
                            icon: "waveform",
                            title: "Voice memos and notes",
                            detail: "Record memories, provenance, condition notes, and context."
                        ),
                        OnboardingHighlight(
                            icon: "doc.richtext",
                            title: "Insurance-ready exports",
                            detail: "Generate PDF, CSV, and data archive exports when you choose."
                        )
                    ]
                )
                .tag(2)

                // Page 4: Permissions
                permissionsPage
                    .tag(3)

                // Page 5: Security
                securityPage
                    .tag(4)
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            // Bottom button
            bottomButton
                .padding(.horizontal, 32)
                .padding(.bottom, 40)
        }
        .onAppear {
            permissionService.refreshStatuses()
        }
        .alert("Security", isPresented: securityAlertBinding) {
            Button("OK") { securityMessage = nil }
        } message: {
            if let securityMessage {
                Text(securityMessage)
            }
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

            Toggle(isOn: faceIDBinding) {
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

    // MARK: - Permissions Page

    private var permissionsPage: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: 72))
                .foregroundStyle(.teal)
                .symbolRenderingMode(.hierarchical)

            VStack(spacing: 10) {
                Text("Permissions")
                    .font(.title.weight(.bold))

                Text("Momento needs camera for 3D scans, microphone for voice memos, and photo library access for attachments.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }

            VStack(spacing: 12) {
                permissionRow(
                    title: "Camera",
                    status: permissionService.cameraStatus
                )
                permissionRow(
                    title: "Microphone",
                    status: permissionService.microphoneStatus
                )
                permissionRow(
                    title: "Photo Library",
                    status: permissionService.photoLibraryStatus
                )
            }
            .padding(.horizontal, 24)

            HStack(spacing: 12) {
                Button {
                    requestPermissions()
                } label: {
                    if isRequestingPermissions {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    } else {
                        Text("Grant Permissions")
                            .frame(maxWidth: .infinity)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isRequestingPermissions)

                Button("Settings") {
                    permissionService.openSystemSettings()
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 24)

            Spacer()
        }
        .padding(.bottom, 8)
    }

    private func permissionRow(title: String, status: PermissionService.PermissionStatus) -> some View {
        HStack {
            Text(title)
                .font(.headline)

            Spacer()

            Label(status.label, systemImage: status.symbolName)
                .labelStyle(.titleAndIcon)
                .font(.subheadline)
                .foregroundStyle(statusColor(status))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
    }

    private func statusColor(_ status: PermissionService.PermissionStatus) -> Color {
        switch status {
        case .authorized:
            .green
        case .denied:
            .red
        case .restricted:
            .orange
        case .notDetermined:
            .secondary
        }
    }

    private func requestPermissions() {
        guard !isRequestingPermissions else { return }
        isRequestingPermissions = true
        Task {
            await permissionService.requestMissingPermissions()
            isRequestingPermissions = false
        }
    }

    // MARK: - Bottom Button

    private var bottomButton: some View {
        Button {
            if currentPage < (pageCount - 1) {
                withAnimation {
                    currentPage += 1
                }
            } else {
                completeOnboarding()
            }
        } label: {
            Text(currentPage < (pageCount - 1) ? "Continue" : "Get Started")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
    }

    // MARK: - Actions

    private var faceIDBinding: Binding<Bool> {
        Binding(
            get: { isFaceIDEnabled },
            set: { newValue in
                handleFaceIDToggle(newValue)
            }
        )
    }

    private var securityAlertBinding: Binding<Bool> {
        Binding(
            get: { securityMessage != nil },
            set: { isPresented in
                if !isPresented {
                    securityMessage = nil
                }
            }
        )
    }

    private func handleFaceIDToggle(_ newValue: Bool) {
        guard newValue else {
            isFaceIDEnabled = false
            return
        }

        Task {
            if await authService.verifyBiometricBeforeEnabling() {
                isFaceIDEnabled = true
            } else {
                isFaceIDEnabled = false
                securityMessage = authService.authError ?? "Momento could not verify your identity."
            }
        }
    }

    private func completeOnboarding() {
        hasSeenOnboarding = true
        dismiss()
    }
}

#Preview {
    OnboardingView()
}

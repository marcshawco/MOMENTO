import SwiftUI

/// Full-screen overlay shown when the app is locked via FaceID.
/// Auto-triggers biometric authentication on appear.
struct LockScreenView: View {

    @Bindable var authService: AuthenticationService

    var body: some View {
        ZStack {
            // Blurred background
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                Image(systemName: "cube.transparent.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.tint)

                Text("Momento")
                    .font(.largeTitle.weight(.bold))

                Text("Tap to unlock your collection")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                if let error = authService.authError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 40)
                }

                Spacer()

                Button {
                    Task {
                        await authService.authenticate()
                    }
                } label: {
                    Label("Unlock with Face ID", systemImage: "faceid")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.borderedProminent)
                .padding(.horizontal, 48)
                .padding(.bottom, 60)
            }
        }
        .task {
            await authService.authenticate()
        }
    }
}

import SwiftUI

/// Reusable onboarding page with an SF Symbol, title, and subtitle.
struct OnboardingPageView: View {

    let systemImage: String
    let imageColor: Color
    let title: String
    let subtitle: String

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: systemImage)
                .font(.system(size: 80))
                .foregroundStyle(imageColor)
                .symbolRenderingMode(.hierarchical)

            VStack(spacing: 12) {
                Text(title)
                    .font(.title.weight(.bold))
                    .multilineTextAlignment(.center)

                Text(subtitle)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()
            Spacer()
        }
        .padding()
    }
}

#Preview {
    OnboardingPageView(
        systemImage: "cube.transparent.fill",
        imageColor: .accentColor,
        title: "Welcome to Momento",
        subtitle: "Create digital twins of your most prized collectibles."
    )
}

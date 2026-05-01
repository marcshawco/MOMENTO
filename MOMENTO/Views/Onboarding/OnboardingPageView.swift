import SwiftUI

struct OnboardingHighlight: Identifiable {
    let id = UUID()
    let icon: String
    let title: String
    let detail: String
}

/// Reusable onboarding page with an SF Symbol, title, and subtitle.
struct OnboardingPageView: View {

    let systemImage: String
    let imageColor: Color
    let title: String
    let subtitle: String
    var highlights: [OnboardingHighlight] = []

    var body: some View {
        VStack(spacing: 22) {
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

            if !highlights.isEmpty {
                VStack(spacing: 12) {
                    ForEach(highlights) { highlight in
                        HStack(alignment: .top, spacing: 12) {
                            Image(systemName: highlight.icon)
                                .font(.headline)
                                .foregroundStyle(imageColor)
                                .frame(width: 24)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(highlight.title)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)

                                Text(highlight.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }

                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(.horizontal, 28)
                .padding(.top, 4)
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
        subtitle: "Create digital twins of your most prized collectibles.",
        highlights: [
            OnboardingHighlight(
                icon: "cube.transparent",
                title: "3D models",
                detail: "Scan supported objects into private USDZ files."
            )
        ]
    )
}

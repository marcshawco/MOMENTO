import SwiftUI

/// Overlay shown while an export operation is in progress.
struct ExportProgressView: View {

    let message: String

    var body: some View {
        ZStack {
            Color.black.opacity(0.3)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                ProgressView()
                    .controlSize(.large)

                Text(message)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
            }
            .padding(32)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
        .transition(.opacity)
    }
}

#Preview {
    ExportProgressView(message: "Generating report...")
}

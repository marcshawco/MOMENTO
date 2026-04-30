import SwiftUI

/// Full-screen container for AR Quick Look with an app-controlled close button.
struct ARPreviewContainerView: View {

    let modelURL: URL
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack(alignment: .topLeading) {
            ARQuickLookView(modelURL: modelURL)
                .ignoresSafeArea()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.black.opacity(0.55), in: Circle())
            }
            .accessibilityLabel("Close AR preview")
            .padding(.top, 16)
            .padding(.leading, 16)
            .zIndex(1)
        }
        .interactiveDismissDisabled(true)
        .statusBarHidden(true)
    }
}

import SwiftUI

/// `UIActivityViewController` wrapper for sharing files (PDF, CSV, etc.).
struct ShareSheetView: UIViewControllerRepresentable {

    let activityItems: [Any]
    var applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: applicationActivities
        )
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {
        // No dynamic updates needed
    }
}

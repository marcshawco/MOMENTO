import QuickLook
import SwiftUI

/// Wraps `QLPreviewController` for AR Quick Look.
/// When given a USDZ file, the system automatically offers the "View in AR" button on supported devices.
struct ARQuickLookView: UIViewControllerRepresentable {

    let modelURL: URL

    func makeUIViewController(context: Context) -> QLPreviewController {
        let controller = QLPreviewController()
        controller.dataSource = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: QLPreviewController, context: Context) {
        // No dynamic updates needed
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(modelURL: modelURL)
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let modelURL: URL

        init(modelURL: URL) {
            self.modelURL = modelURL
            super.init()
        }

        func numberOfPreviewItems(in controller: QLPreviewController) -> Int {
            1
        }

        func previewController(
            _ controller: QLPreviewController,
            previewItemAt index: Int
        ) -> any QLPreviewItem {
            modelURL as NSURL
        }
    }
}

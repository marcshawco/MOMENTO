import SceneKit
import SwiftUI

/// Embedded 3D model preview using SceneKit's SceneView.
/// Shows an interactive camera-controllable render of the USDZ model, or a placeholder if none exists.
struct ModelPreviewView: View {

    let modelURL: URL?

    @State private var scene: SCNScene?
    @State private var loadFailed = false

    var body: some View {
        Group {
            if let scene {
                SceneView(
                    scene: scene,
                    options: [.allowsCameraControl, .autoenablesDefaultLighting]
                )
            } else {
                placeholderView
            }
        }
        .frame(height: AppConstants.Detail.modelPreviewHeight)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .task {
            loadScene()
        }
    }

    // MARK: - Placeholder

    private var placeholderView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16)
                .fill(.quaternary)

            VStack(spacing: 12) {
                Image(systemName: loadFailed ? "exclamationmark.triangle" : "cube.transparent")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)

                Text(loadFailed ? "Failed to load model" : "No 3D Model")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Loading

    private func loadScene() {
        guard let modelURL else { return }

        let path = modelURL.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: path) else { return }

        do {
            let loadedScene = try SCNScene(url: modelURL)

            // Set a pleasant background
            loadedScene.background.contents = UIColor.systemGroupedBackground

            scene = loadedScene
        } catch {
            loadFailed = true
        }
    }
}

#Preview("With Model") {
    ModelPreviewView(modelURL: nil)
        .padding()
}

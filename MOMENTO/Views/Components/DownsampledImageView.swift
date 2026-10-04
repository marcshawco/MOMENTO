import ImageIO
import SwiftUI
import UIKit

/// Renders a file-backed image using downsampling to avoid decoding full-resolution assets in small cells.
struct DownsampledImageView: View {

    let url: URL
    let targetSize: CGSize
    var contentMode: ContentMode = .fill

    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?
    @State private var failed = false

    var body: some View {
        Group {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else if failed {
                Rectangle()
                    .fill(.quaternary)
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    }
            } else {
                ZStack {
                    Rectangle().fill(.quaternary)
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
        .task(id: TaskKey(url: url, scale: displayScale)) {
            await load(scale: displayScale)
        }
    }

    private func load(scale: CGFloat) async {
        let targetSize = targetSize
        let url = url
        do {
            let maybeImage = try await Task.detached(priority: .userInitiated) {
                try Self.downsampleImage(at: url, to: targetSize, scale: scale)
            }.value

            image = maybeImage
            failed = maybeImage == nil
        } catch {
            failed = true
        }
    }

    /// Re-runs the load when either the file or the display scale changes.
    private struct TaskKey: Equatable {
        let url: URL
        let scale: CGFloat
    }

    nonisolated private static func downsampleImage(
        at imageURL: URL,
        to pointSize: CGSize,
        scale: CGFloat
    ) throws -> UIImage? {
        let sourceOptions: CFDictionary = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(imageURL as CFURL, sourceOptions) else {
            return nil
        }

        let maxDimensionInPixels = max(pointSize.width, pointSize.height) * scale
        let downsampleOptions: CFDictionary = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxDimensionInPixels,
        ] as CFDictionary

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, downsampleOptions) else {
            return nil
        }

        return UIImage(cgImage: cgImage)
    }
}

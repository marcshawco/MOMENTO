import ImageIO
import SwiftUI
import UIKit

/// Renders a file-backed image using downsampling to avoid decoding full-resolution assets in small cells.
struct DownsampledImageView: View {

    let url: URL
    let targetSize: CGSize
    var contentMode: ContentMode = .fill

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
        .task(id: url) {
            await load()
        }
    }

    private func load() async {
        let screenScale = await MainActor.run { UIScreen.main.scale }
        do {
            let maybeImage = try await Task.detached(priority: .userInitiated) {
                try Self.downsampleImage(at: url, to: targetSize, scale: screenScale)
            }.value

            await MainActor.run {
                image = maybeImage
                failed = maybeImage == nil
            }
        } catch {
            await MainActor.run {
                failed = true
            }
        }
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

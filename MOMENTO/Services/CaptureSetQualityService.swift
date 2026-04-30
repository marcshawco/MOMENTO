import CoreGraphics
import Foundation
import ImageIO
import os

enum CaptureSetQualityIssue: String, CaseIterable, Sendable {
    case tooFewImages
    case tooFewUsableImages
    case tooDark
    case tooBright
    case tooSoft

    nonisolated var userMessage: String {
        switch self {
        case .tooFewImages:
            "Capture more angles before reconstructing."
        case .tooFewUsableImages:
            "Several images look weak. Rescan with slower movement and steadier framing."
        case .tooDark:
            "Lighting is too low for reliable surface matching."
        case .tooBright:
            "Lighting is blown out. Reduce glare or move away from direct reflections."
        case .tooSoft:
            "Images look soft. Move slower and keep the object size steady."
        }
    }
}

struct CaptureSetQualityMetrics: Equatable, Sendable {
    let totalImages: Int
    let analyzedImages: Int
    let usableImages: Int
    let averageBrightness: Double
    let averageSharpness: Double
}

struct CaptureSetQualityReport: Equatable, Sendable {
    let metrics: CaptureSetQualityMetrics
    let issues: [CaptureSetQualityIssue]

    nonisolated var isReconstructionReady: Bool {
        issues.isEmpty
    }

    nonisolated var userMessage: String {
        guard !issues.isEmpty else {
            return "Capture set looks ready for high-detail reconstruction."
        }

        return issues.map(\.userMessage).joined(separator: " ")
    }
}

final class CaptureSetQualityService {
    static let shared = CaptureSetQualityService()

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Momento", category: "CaptureSetQuality")

    private init() {}

    func assessImageSet(at directory: URL) async -> CaptureSetQualityReport {
        await Task.detached(priority: .utility) { [logger] in
            let imageURLs = Self.imageURLs(in: directory)
            let samples = imageURLs.compactMap { Self.analyzeImage(at: $0) }
            let metrics = Self.metrics(totalImages: imageURLs.count, samples: samples)
            let report = Self.evaluate(metrics: metrics)

            if !report.isReconstructionReady {
                logger.warning("Capture set quality check failed: \(report.userMessage)")
            }

            return report
        }.value
    }

    nonisolated static func evaluate(metrics: CaptureSetQualityMetrics) -> CaptureSetQualityReport {
        var issues: [CaptureSetQualityIssue] = []
        let usableRatio = metrics.totalImages == 0 ? 0 : Double(metrics.usableImages) / Double(metrics.totalImages)

        if metrics.totalImages < 24 {
            issues.append(.tooFewImages)
        }

        if usableRatio < 0.72 {
            issues.append(.tooFewUsableImages)
        }

        if metrics.analyzedImages > 0 && metrics.averageBrightness < 0.16 {
            issues.append(.tooDark)
        }

        if metrics.analyzedImages > 0 && metrics.averageBrightness > 0.88 {
            issues.append(.tooBright)
        }

        if metrics.analyzedImages > 0 && metrics.averageSharpness < 0.018 {
            issues.append(.tooSoft)
        }

        return CaptureSetQualityReport(metrics: metrics, issues: issues)
    }

    nonisolated private static func imageURLs(in directory: URL) -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return urls
            .filter { ["jpg", "jpeg", "heic", "png"].contains($0.pathExtension.lowercased()) }
            .sorted {
                let leftDate = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let rightDate = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return leftDate < rightDate
            }
    }

    nonisolated private static func metrics(totalImages: Int, samples: [ImageQualitySample]) -> CaptureSetQualityMetrics {
        guard !samples.isEmpty else {
            return CaptureSetQualityMetrics(
                totalImages: totalImages,
                analyzedImages: 0,
                usableImages: 0,
                averageBrightness: 0,
                averageSharpness: 0
            )
        }

        let usableImages = samples.filter(\.isUsable).count
        let brightness = samples.map(\.brightness).reduce(0, +) / Double(samples.count)
        let sharpness = samples.map(\.sharpness).reduce(0, +) / Double(samples.count)

        return CaptureSetQualityMetrics(
            totalImages: totalImages,
            analyzedImages: samples.count,
            usableImages: usableImages,
            averageBrightness: brightness,
            averageSharpness: sharpness
        )
    }

    nonisolated private static func analyzeImage(at url: URL) -> ImageQualitySample? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: 96
        ]

        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              let dataProvider = image.dataProvider,
              let data = dataProvider.data,
              let bytes = CFDataGetBytePtr(data) else {
            return nil
        }

        let width = image.width
        let height = image.height
        let bytesPerRow = image.bytesPerRow
        let bytesPerPixel = max(1, image.bitsPerPixel / 8)

        guard width > 2, height > 2, bytesPerPixel >= 3 else { return nil }

        var luminance = Array(repeating: 0.0, count: width * height)
        var luminanceTotal = 0.0

        for y in 0..<height {
            for x in 0..<width {
                let offset = y * bytesPerRow + x * bytesPerPixel
                let red = Double(bytes[offset]) / 255.0
                let green = Double(bytes[offset + 1]) / 255.0
                let blue = Double(bytes[offset + 2]) / 255.0
                let value = 0.2126 * red + 0.7152 * green + 0.0722 * blue
                luminance[y * width + x] = value
                luminanceTotal += value
            }
        }

        let brightness = luminanceTotal / Double(width * height)
        let sharpness = edgeEnergy(in: luminance, width: width, height: height)
        let isUsable = brightness >= 0.12 && brightness <= 0.92 && sharpness >= 0.012

        return ImageQualitySample(brightness: brightness, sharpness: sharpness, isUsable: isUsable)
    }

    nonisolated private static func edgeEnergy(in luminance: [Double], width: Int, height: Int) -> Double {
        var total = 0.0
        var count = 0

        for y in 1..<(height - 1) {
            for x in 1..<(width - 1) {
                let center = luminance[y * width + x]
                let laplacian = abs(
                    (4.0 * center)
                    - luminance[y * width + x - 1]
                    - luminance[y * width + x + 1]
                    - luminance[(y - 1) * width + x]
                    - luminance[(y + 1) * width + x]
                )
                total += laplacian
                count += 1
            }
        }

        guard count > 0 else { return 0 }
        return total / Double(count)
    }
}

private struct ImageQualitySample {
    let brightness: Double
    let sharpness: Double
    let isUsable: Bool
}

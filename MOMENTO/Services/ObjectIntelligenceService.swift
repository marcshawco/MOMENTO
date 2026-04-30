import CoreML
import Foundation
import ImageIO
import UIKit
import Vision
import os

struct ObjectMetadataSuggestion: Sendable {
    let title: String
    let collectionName: String
    let tags: [String]
    let confidence: Float
}

final class ObjectIntelligenceService {
    static let shared = ObjectIntelligenceService()

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Momento", category: "ObjectIntelligence")
    private let userDefaults = UserDefaults.standard

    private init() {}

    func suggestMetadata(from imagesDirectory: URL) async -> ObjectMetadataSuggestion? {
        guard let imageURL = representativeImageURL(in: imagesDirectory),
              let imageData = try? Data(contentsOf: imageURL) else {
            return nil
        }

        var bestSuggestion: ObjectMetadataSuggestion?

        if isOnDeviceSuggestionEnabled {
            bestSuggestion = await onDeviceSuggestion(from: imageData)
        }

        if isCloudSuggestionEnabled,
           (bestSuggestion == nil || (bestSuggestion?.confidence ?? 0) < 0.55),
           let cloudSuggestion = await cloudSuggestion(from: imageData) {
            bestSuggestion = cloudSuggestion
        }

        return bestSuggestion
    }

    private var isOnDeviceSuggestionEnabled: Bool {
        bool(for: AppConstants.UserDefaultsKeys.enableOnDeviceSuggestions, defaultValue: true)
    }

    private var isCloudSuggestionEnabled: Bool {
        bool(for: AppConstants.UserDefaultsKeys.enableCloudSuggestions, defaultValue: false)
    }

    private func bool(for key: String, defaultValue: Bool) -> Bool {
        guard userDefaults.object(forKey: key) != nil else { return defaultValue }
        return userDefaults.bool(forKey: key)
    }

    private func representativeImageURL(in directory: URL) -> URL? {
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return nil }

        let jpgs = urls.filter {
            let ext = $0.pathExtension.lowercased()
            return ext == "jpg" || ext == "jpeg" || ext == "heic"
        }

        let sorted = jpgs.sorted {
            let leftDate = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let rightDate = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return leftDate < rightDate
        }

        guard !sorted.isEmpty else { return nil }
        return sorted[sorted.count / 2]
    }

    private func onDeviceSuggestion(from imageData: Data) async -> ObjectMetadataSuggestion? {
        await Task.detached(priority: .utility) {
            guard let cgImage = Self.makeCGImage(from: imageData) else { return nil }

            let observations = (try? Self.runClassification(cgImage: cgImage)) ?? []
            return Self.makeSuggestion(from: observations)
        }.value
    }

    nonisolated private static func makeCGImage(from data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    nonisolated private static func runClassification(cgImage: CGImage) throws -> [VNClassificationObservation] {
        if let request = makeCoreMLRequest() {
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            try handler.perform([request])
            return (request.results as? [VNClassificationObservation]) ?? []
        }

        let request = VNClassifyImageRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])
        return request.results ?? []
    }

    nonisolated private static func makeCoreMLRequest() -> VNCoreMLRequest? {
        guard let modelURL = Bundle.main.url(forResource: "CollectibleClassifier", withExtension: "mlmodelc") else {
            return nil
        }

        do {
            let model = try MLModel(contentsOf: modelURL)
            let visionModel = try VNCoreMLModel(for: model)
            return VNCoreMLRequest(model: visionModel)
        } catch {
            return nil
        }
    }

    nonisolated private static func makeSuggestion(from observations: [VNClassificationObservation]) -> ObjectMetadataSuggestion? {
        guard let best = observations.first, best.confidence > 0.2 else { return nil }

        let primaryLabel = normalizedLabel(best.identifier)
        let match = categoryMatch(for: primaryLabel)

        let title = match?.title ?? primaryLabel.capitalized
        let collectionName = match?.category ?? "Collectibles"

        let topLabels = observations.prefix(3).map { normalizedLabel($0.identifier) }
        var tags = Set<String>()
        tags.insert(collectionName.lowercased())
        match?.tags.forEach { tags.insert($0) }
        topLabels.forEach { label in
            for token in label.split(separator: " ") where token.count > 2 {
                tags.insert(token.lowercased())
            }
        }

        return ObjectMetadataSuggestion(
            title: title,
            collectionName: collectionName,
            tags: Array(tags).sorted().prefix(6).map { String($0) },
            confidence: best.confidence
        )
    }

    nonisolated private static func normalizedLabel(_ raw: String) -> String {
        let base = raw.split(separator: ",").first.map(String.init) ?? raw
        return base
            .replacingOccurrences(of: "_", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    nonisolated private static func categoryMatch(for label: String) -> (category: String, title: String, tags: [String])? {
        let lower = label.lowercased()

        let rules: [([String], String, String, [String])] = [
            (["coin", "currency", "token", "medal"], "Coins", "Coin Collectible", ["numismatic"]),
            (["watch", "clock"], "Watches", "Watch Collectible", ["timepiece"]),
            (["card", "trading card"], "Cards", "Card Collectible", ["trading-card"]),
            (["figure", "figurine", "statue", "toy"], "Figures", "Figure Collectible", ["display"]),
            (["comic", "book"], "Comics", "Comic Collectible", ["paper"]),
            (["shoe", "sneaker", "boot"], "Sneakers", "Sneaker Collectible", ["footwear"]),
            (["bottle", "cup", "mug", "glass"], "Drinkware", "Drinkware Collectible", ["vessel"]),
            (["camera", "console", "phone", "radio"], "Electronics", "Electronic Collectible", ["device"])
        ]

        for (keywords, category, title, tags) in rules where keywords.contains(where: { lower.contains($0) }) {
            return (category, title, tags)
        }

        return nil
    }

    private struct CloudSuggestionRequest: Encodable {
        let imageBase64: String
    }

    private struct CloudSuggestionResponse: Decodable {
        let title: String?
        let collectionName: String?
        let tags: [String]?
        let confidence: Double?
    }

    private func cloudSuggestion(from imageData: Data) async -> ObjectMetadataSuggestion? {
        let rawEndpoint = userDefaults.string(forKey: AppConstants.UserDefaultsKeys.cloudSuggestionEndpoint) ?? ""
        guard let endpointURL = Self.normalizedAllowedCloudSuggestionEndpoint(rawEndpoint) else {
            logger.warning("Cloud suggestion enabled but endpoint is missing or not an allowed HTTPS URL")
            return nil
        }

        guard let downsampledData = downsampleJPEG(from: imageData, maxDimension: 640) else { return nil }

        do {
            var request = URLRequest(url: endpointURL)
            request.httpMethod = "POST"
            request.timeoutInterval = 12
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONEncoder().encode(
                CloudSuggestionRequest(imageBase64: downsampledData.base64EncodedString())
            )

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }

            let decoded = try JSONDecoder().decode(CloudSuggestionResponse.self, from: data)
            guard let rawTitle = decoded.title?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !rawTitle.isEmpty else {
                return nil
            }

            let normalizedTags = (decoded.tags ?? [])
                .map { $0.lowercased().trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }

            let collectionName = decoded.collectionName?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedCollectionName: String
            if let collectionName, !collectionName.isEmpty {
                resolvedCollectionName = collectionName
            } else {
                resolvedCollectionName = "Collectibles"
            }

            return ObjectMetadataSuggestion(
                title: rawTitle,
                collectionName: resolvedCollectionName,
                tags: Array(Set(normalizedTags)).sorted().prefix(6).map { String($0) },
                confidence: Float(decoded.confidence ?? 0.6)
            )
        } catch {
            logger.warning("Cloud suggestion request failed: \(error.localizedDescription)")
            return nil
        }
    }

    private func downsampleJPEG(from data: Data, maxDimension: CGFloat) -> Data? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: Int(maxDimension),
            kCGImageSourceCreateThumbnailWithTransform: true
        ]

        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let uiImage = UIImage(cgImage: image)
        return uiImage.jpegData(compressionQuality: 0.8)
    }

    nonisolated static func isAllowedCloudSuggestionEndpoint(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https" else {
            return false
        }

        return url.host?.isEmpty == false
    }

    nonisolated static func normalizedAllowedCloudSuggestionEndpoint(_ rawEndpoint: String) -> URL? {
        let endpointString = rawEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !endpointString.isEmpty,
              let endpointURL = URL(string: endpointString),
              isAllowedCloudSuggestionEndpoint(endpointURL) else {
            return nil
        }

        return endpointURL
    }
}

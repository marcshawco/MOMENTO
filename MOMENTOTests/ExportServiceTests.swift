import Foundation
import ImageIO
import UIKit
import XCTest
@testable import MOMENTO

final class ExportServiceTests: XCTestCase {

    override func tearDown() {
        ExportService.shared.cleanupExportFiles()
        super.tearDown()
    }

    func testCSVExportEscapesCommasQuotesAndIncludesAssetColumns() throws {
        let item = CollectionItem(
            title: "Vintage \"Proof\", Coin",
            itemDescription: "Graded, boxed",
            tags: ["rare", "silver"],
            collectionName: "Coins",
            serialNumber: "ABC-123",
            modelFileName: "Models/example.usdz",
            thumbnailFileName: "Thumbnails/example.png"
        )

        let url = try ExportService.shared.generateCSV(items: [item])
        let csv = try String(contentsOf: url, encoding: .utf8)

        XCTAssertTrue(csv.contains("Model File,Thumbnail File"))
        XCTAssertTrue(csv.contains("\"Vintage \"\"Proof\"\", Coin\""))
        XCTAssertTrue(csv.contains("Models/example.usdz"))
        XCTAssertTrue(csv.contains("Thumbnails/example.png"))
    }

    func testExportsRejectEmptyItemSets() {
        XCTAssertThrowsError(try ExportService.shared.generatePDFReport(items: [])) { error in
            XCTAssertEqual(error as? ExportService.ExportError, .noItems)
        }
        XCTAssertThrowsError(try ExportService.shared.generateCSV(items: [])) { error in
            XCTAssertEqual(error as? ExportService.ExportError, .noItems)
        }
        XCTAssertThrowsError(try ExportService.shared.generateDataArchive(items: [])) { error in
            XCTAssertEqual(error as? ExportService.ExportError, .noItems)
        }
    }

    func testDataArchiveManifestIncludesAssetsWithChecksums() throws {
        FileStorageService.shared.createDirectoryStructure()
        let id = UUID()
        let modelPath = try FileStorageService.shared.saveFile(
            data: Data("model-data".utf8),
            directory: AppConstants.Storage.modelsFolder,
            fileName: "\(id.uuidString).usdz"
        )
        let photoPath = try FileStorageService.shared.saveFile(
            data: try makeJPEGWithGPSMetadata(),
            directory: AppConstants.Storage.photosFolder,
            fileName: "\(id.uuidString).jpg"
        )
        defer {
            FileStorageService.shared.deleteFile(fileName: modelPath)
            FileStorageService.shared.deleteFile(fileName: photoPath)
        }

        let item = CollectionItem(
            id: id,
            title: "Archive Item",
            tags: ["archive"],
            collectionName: "Tests",
            modelFileName: modelPath
        )
        let photo = PhotoAttachment(fileName: photoPath, caption: "Front angle")
        item.photoAttachments.append(photo)

        let manifest = ExportService.shared.makeDataArchiveManifest(items: [item])

        XCTAssertEqual(manifest.schemaVersion, 1)
        XCTAssertEqual(manifest.itemCount, 1)
        XCTAssertEqual(manifest.items.first?.assets.count, 2)
        XCTAssertEqual(manifest.items.first?.photoCaptions[photoPath], "Front angle")
        XCTAssertTrue(manifest.items.first?.assets.allSatisfy { $0.byteCount != nil && $0.sha256 != nil } ?? false)
    }

    func testDataArchiveReturnsManifestAndExistingAssetURLs() throws {
        FileStorageService.shared.createDirectoryStructure()
        let id = UUID()
        let modelPath = try FileStorageService.shared.saveFile(
            data: Data("model-data".utf8),
            directory: AppConstants.Storage.modelsFolder,
            fileName: "\(id.uuidString).usdz"
        )
        defer {
            FileStorageService.shared.deleteFile(fileName: modelPath)
        }

        let item = CollectionItem(
            id: id,
            title: "Share Item",
            modelFileName: modelPath
        )

        let urls = try ExportService.shared.generateDataArchive(items: [item])

        XCTAssertEqual(urls.count, 2)
        XCTAssertEqual(urls.first?.pathExtension, "json")
        XCTAssertEqual(urls.last?.lastPathComponent, "\(id.uuidString).usdz")
    }

    func testDataArchiveExportsSanitizedPhotoCopy() throws {
        FileStorageService.shared.createDirectoryStructure()
        let id = UUID()
        let photoPath = try FileStorageService.shared.saveFile(
            data: try makeJPEGWithGPSMetadata(),
            directory: AppConstants.Storage.photosFolder,
            fileName: "\(id.uuidString).jpg"
        )
        defer {
            FileStorageService.shared.deleteFile(fileName: photoPath)
        }

        let item = CollectionItem(id: id, title: "Legacy Photo Item")
        item.photoAttachments.append(PhotoAttachment(fileName: photoPath, item: item))

        let urls = try ExportService.shared.generateDataArchive(items: [item])
        let exportedPhotoURL = try XCTUnwrap(urls.first { $0.lastPathComponent.hasPrefix("sanitized-") })
        let storedURL = try FileStorageService.shared.resolveURL(for: photoPath)

        XCTAssertNotEqual(exportedPhotoURL, storedURL)
        XCTAssertNil(try gpsMetadata(in: exportedPhotoURL))
    }

    private func gpsMetadata(in url: URL) throws -> Any? {
        let data = try Data(contentsOf: url)
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else {
            return nil
        }
        return properties[kCGImagePropertyGPSDictionary]
    }

    private func makeJPEGWithGPSMetadata() throws -> Data {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 2, height: 2))
        }

        guard let cgImage = image.cgImage else {
            throw TestImageError.missingCGImage
        }

        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data,
            "public.jpeg" as CFString,
            1,
            nil
        ) else {
            throw TestImageError.missingDestination
        }

        let gpsMetadata: [CFString: Any] = [
            kCGImagePropertyGPSLatitude: 37.3317,
            kCGImagePropertyGPSLatitudeRef: "N",
            kCGImagePropertyGPSLongitude: 122.0307,
            kCGImagePropertyGPSLongitudeRef: "W",
        ]
        let properties: [CFString: Any] = [
            kCGImagePropertyGPSDictionary: gpsMetadata,
            kCGImagePropertyOrientation: 1,
        ]

        CGImageDestinationAddImage(destination, cgImage, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else {
            throw TestImageError.finalizeFailed
        }

        return data as Data
    }

    private enum TestImageError: Error {
        case missingCGImage
        case missingDestination
        case finalizeFailed
    }
}

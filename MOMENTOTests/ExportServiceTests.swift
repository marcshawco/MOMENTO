import Foundation
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

    func testDataArchiveManifestIncludesAssetsWithChecksums() throws {
        FileStorageService.shared.createDirectoryStructure()
        let id = UUID()
        let modelPath = try FileStorageService.shared.saveFile(
            data: Data("model-data".utf8),
            directory: AppConstants.Storage.modelsFolder,
            fileName: "\(id.uuidString).usdz"
        )
        let photoPath = try FileStorageService.shared.saveFile(
            data: Data("photo-data".utf8),
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
}

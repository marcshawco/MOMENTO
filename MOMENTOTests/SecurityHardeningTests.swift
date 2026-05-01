import XCTest
@testable import MOMENTO

final class SecurityHardeningTests: XCTestCase {

    func testResolveURLRejectsTraversalPaths() {
        XCTAssertThrowsError(try FileStorageService.shared.resolveURL(for: "../Library/private.jpg"))
        XCTAssertThrowsError(try FileStorageService.shared.resolveURL(for: "Photos/../../private.jpg"))
        XCTAssertThrowsError(try FileStorageService.shared.resolveURL(for: "/tmp/private.jpg"))
        XCTAssertThrowsError(try FileStorageService.shared.resolveURL(for: "Photos//private.jpg"))
    }

    func testSaveFileRejectsNestedOrTraversalFileNames() {
        XCTAssertThrowsError(
            try FileStorageService.shared.saveFile(
                data: Data("bad".utf8),
                directory: AppConstants.Storage.photosFolder,
                fileName: "../escape.jpg"
            )
        )
        XCTAssertThrowsError(
            try FileStorageService.shared.saveFile(
                data: Data("bad".utf8),
                directory: AppConstants.Storage.photosFolder,
                fileName: "nested/escape.jpg"
            )
        )
    }

    func testResolveURLAllowsManagedRelativePath() throws {
        let url = try FileStorageService.shared.resolveURL(for: "Photos/item.jpg")

        XCTAssertTrue(url.path(percentEncoded: false).contains("/Momento/Photos/item.jpg"))
    }

    func testCleanupUnreferencedFilesPreservesReferencedAssetsAndDeletesOrphans() throws {
        FileStorageService.shared.createDirectoryStructure()
        let id = UUID().uuidString
        let referenced = try FileStorageService.shared.saveFile(
            data: Data(repeating: 1, count: 8),
            directory: AppConstants.Storage.photosFolder,
            fileName: "\(id)-referenced.jpg"
        )
        let orphan = try FileStorageService.shared.saveFile(
            data: Data(repeating: 2, count: 16),
            directory: AppConstants.Storage.photosFolder,
            fileName: "\(id)-orphan.jpg"
        )
        defer {
            FileStorageService.shared.deleteFile(fileName: referenced)
            FileStorageService.shared.deleteFile(fileName: orphan)
        }

        let summary = FileStorageService.shared.cleanupUnreferencedFiles(referencedFileNames: [referenced])

        XCTAssertGreaterThanOrEqual(summary.deletedFiles, 1)
        XCTAssertTrue(FileStorageService.shared.fileExists(fileName: referenced))
        XCTAssertFalse(FileStorageService.shared.fileExists(fileName: orphan))
    }

    func testCleanupAllCaptureTempRemovesSessionDirectories() throws {
        let sessionId = UUID().uuidString
        let sessionDirectory = try FileStorageService.shared.captureTempDirectory(sessionId: sessionId)
        let tempFile = sessionDirectory.appendingPathComponent("frame.jpg")
        try Data(repeating: 3, count: 32).write(to: tempFile)

        let summary = FileStorageService.shared.cleanupAllCaptureTemp()

        XCTAssertGreaterThanOrEqual(summary.deletedFiles, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: sessionDirectory.path(percentEncoded: false)))
    }

    func testCloudSuggestionEndpointRequiresHTTPS() throws {
        let httpsURL = try XCTUnwrap(URL(string: "https://example.com/suggest"))
        let httpURL = try XCTUnwrap(URL(string: "http://example.com/suggest"))
        let fileURL = URL(fileURLWithPath: "/tmp/suggest")

        XCTAssertTrue(ObjectIntelligenceService.isAllowedCloudSuggestionEndpoint(httpsURL))
        XCTAssertFalse(ObjectIntelligenceService.isAllowedCloudSuggestionEndpoint(httpURL))
        XCTAssertFalse(ObjectIntelligenceService.isAllowedCloudSuggestionEndpoint(fileURL))
    }

    func testCloudSuggestionEndpointNormalizationTrimsAndRejectsInvalidValues() throws {
        let normalizedURL = try XCTUnwrap(
            ObjectIntelligenceService.normalizedAllowedCloudSuggestionEndpoint("  https://example.com/suggest  ")
        )

        XCTAssertEqual(normalizedURL.absoluteString, "https://example.com/suggest")
        XCTAssertNil(ObjectIntelligenceService.normalizedAllowedCloudSuggestionEndpoint(""))
        XCTAssertNil(ObjectIntelligenceService.normalizedAllowedCloudSuggestionEndpoint("example.com/suggest"))
        XCTAssertNil(ObjectIntelligenceService.normalizedAllowedCloudSuggestionEndpoint("http://example.com/suggest"))
    }
}

import XCTest
@testable import MOMENTO

final class SecurityHardeningTests: XCTestCase {

    func testResolveURLRejectsTraversalPaths() {
        XCTAssertThrowsError(try FileStorageService.shared.resolveURL(for: "../Library/private.jpg"))
        XCTAssertThrowsError(try FileStorageService.shared.resolveURL(for: "Photos/../../private.jpg"))
        XCTAssertThrowsError(try FileStorageService.shared.resolveURL(for: "/tmp/private.jpg"))
        XCTAssertThrowsError(try FileStorageService.shared.resolveURL(for: "Photos//private.jpg"))
    }

    func testResolveURLAllowsManagedRelativePath() throws {
        let url = try FileStorageService.shared.resolveURL(for: "Photos/item.jpg")

        XCTAssertTrue(url.path(percentEncoded: false).contains("/Momento/Photos/item.jpg"))
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

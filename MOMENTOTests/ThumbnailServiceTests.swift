import ImageIO
import UIKit
import XCTest
@testable import MOMENTO

final class ThumbnailServiceTests: XCTestCase {

    func testCaptureThumbnailUsesRepresentativeImageWithoutModelRendering() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MomentoThumbnailServiceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        let imageURL = directory.appendingPathComponent("capture-001.jpg")
        try makeJPEGData().write(to: imageURL, options: [.atomic])

        let thumbnailData = try await ThumbnailService.shared.generateCaptureThumbnail(from: directory, size: 96)

        XCTAssertFalse(thumbnailData.isEmpty)
        XCTAssertNotNil(UIImage(data: thumbnailData))
    }

    func testCaptureThumbnailThrowsForEmptyDirectory() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("MomentoThumbnailServiceTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }

        do {
            _ = try await ThumbnailService.shared.generateCaptureThumbnail(from: directory, size: 96)
            XCTFail("Expected empty capture directory to throw")
        } catch let error as ThumbnailService.ThumbnailError {
            XCTAssertEqual(error.localizedDescription, ThumbnailService.ThumbnailError.noRepresentativeImage.localizedDescription)
        }
    }

    private func makeJPEGData() throws -> Data {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 16, height: 16)).image { context in
            UIColor.systemBlue.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
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

        CGImageDestinationAddImage(destination, cgImage, nil)
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

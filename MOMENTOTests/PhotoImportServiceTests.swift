import ImageIO
import UIKit
import XCTest
@testable import MOMENTO

final class PhotoImportServiceTests: XCTestCase {

    func testSanitizedImageDataRemovesGPSMetadata() throws {
        let imageData = try makeJPEGWithGPSMetadata()

        let sanitizedData = try PhotoImportService.shared.sanitizedImageData(from: imageData)

        guard let source = CGImageSourceCreateWithData(sanitizedData as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else {
            XCTFail("Expected readable sanitized image metadata")
            return
        }

        XCTAssertNil(properties[kCGImagePropertyGPSDictionary])
    }

    func testImportPhotoStoresSanitizedFile() throws {
        let imageData = try makeJPEGWithGPSMetadata()

        let relativePath = try PhotoImportService.shared.importPhoto(imageData: imageData)
        defer {
            FileStorageService.shared.deleteFile(fileName: relativePath)
        }

        let storedURL = try FileStorageService.shared.resolveURL(for: relativePath)
        let storedData = try Data(contentsOf: storedURL)
        guard let source = CGImageSourceCreateWithData(storedData as CFData, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else {
            XCTFail("Expected readable stored image metadata")
            return
        }

        XCTAssertNil(properties[kCGImagePropertyGPSDictionary])
    }

    private func makeJPEGWithGPSMetadata() throws -> Data {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 2, height: 2)).image { context in
            UIColor.systemRed.setFill()
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

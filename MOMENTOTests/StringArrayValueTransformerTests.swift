import XCTest
@testable import MOMENTO

final class StringArrayValueTransformerTests: XCTestCase {

    private let transformer = StringArrayValueTransformer()

    func testRoundTripEncodesAndDecodesTags() {
        let tags = ["camera", "vintage", "Leica"]

        let encoded = transformer.transformedValue(tags) as? Data
        XCTAssertNotNil(encoded)

        let decoded = transformer.reverseTransformedValue(encoded) as? [String]
        XCTAssertEqual(decoded, tags)
    }

    func testRoundTripHandlesEmptyArray() {
        let encoded = transformer.transformedValue([]) as? Data
        XCTAssertNotNil(encoded)

        let decoded = transformer.reverseTransformedValue(encoded) as? [String]
        XCTAssertEqual(decoded, [])
    }

    func testMalformedPayloadReturnsEmptyArray() {
        let malformed = Data([0xDE, 0xAD, 0xBE, 0xEF])

        let decoded = transformer.reverseTransformedValue(malformed) as? [String]
        XCTAssertEqual(decoded, [])
    }
}

import XCTest
@testable import Murmur

final class ClipboardExtractorTests: XCTestCase {

    func testCleanNormalizesWhitespaceWithoutTruncatingLongArticles() {
        let paragraph = String(repeating: "A useful sentence with several words. ", count: 400)

        let cleaned = ClipboardExtractor.clean(paragraph, maxLength: 100_000)

        XCTAssertNotNil(cleaned)
        XCTAssertGreaterThan(cleaned?.count ?? 0, 10_000)
    }

    func testCleanTruncatesAtLastSentenceBoundary() {
        let cleaned = ClipboardExtractor.clean(
            "First sentence. Second sentence continues for a while.",
            maxLength: 30
        )

        XCTAssertEqual(cleaned, "First sentence.")
    }
}

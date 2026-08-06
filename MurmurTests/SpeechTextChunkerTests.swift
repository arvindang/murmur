import XCTest
@testable import Murmur

final class SpeechTextChunkerTests: XCTestCase {

    func testEmptyAndWhitespaceOnlyTextProducesNoChunks() {
        XCTAssertTrue(SpeechTextChunker.chunks(for: "", maxCharacters: 100).isEmpty)
        XCTAssertTrue(SpeechTextChunker.chunks(for: "  \n\t ", maxCharacters: 100).isEmpty)
    }

    func testLongSentenceNeverExceedsLimit() {
        let text = String(repeating: "a", count: 4_501)
        let chunks = SpeechTextChunker.chunks(for: text, maxCharacters: 2_000)

        XCTAssertEqual(chunks.map(\.count), [2_000, 2_000, 501])
        XCTAssertTrue(chunks.allSatisfy { $0.count <= 2_000 })
        XCTAssertEqual(chunks.joined(), text)
    }

    func testSentenceChunksPreserveNormalizedText() {
        let input = (1...80)
            .map { "Sentence \($0) has enough words to exercise chunking." }
            .joined(separator: "  \n")
        let expected = input
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let chunks = SpeechTextChunker.chunks(for: input, maxCharacters: 240)

        XCTAssertGreaterThan(chunks.count, 1)
        XCTAssertTrue(chunks.allSatisfy { !$0.isEmpty && $0.count <= 240 })
        XCTAssertEqual(chunks.joined(separator: " "), expected)
    }

    func testUnicodeUsesCharacterLimitRatherThanUTF8ByteLimit() {
        let text = String(repeating: "🙂", count: 205)
        let chunks = SpeechTextChunker.chunks(for: text, maxCharacters: 100)

        XCTAssertEqual(chunks.map(\.count), [100, 100, 5])
        XCTAssertEqual(chunks.joined(), text)
    }
}

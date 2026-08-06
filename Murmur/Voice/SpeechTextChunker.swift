import Foundation
import NaturalLanguage

/// Splits long-form text into speech-friendly chunks without exceeding an API limit.
enum SpeechTextChunker {

    static func chunks(for text: String, maxCharacters: Int) -> [String] {
        precondition(maxCharacters > 0)

        let normalized = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !normalized.isEmpty else { return [] }
        guard normalized.count > maxCharacters else { return [normalized] }

        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = normalized

        var sentences: [String] = []
        tokenizer.enumerateTokens(in: normalized.startIndex..<normalized.endIndex) { range, _ in
            sentences.append(String(normalized[range]))
            return true
        }
        if sentences.isEmpty { sentences = [normalized] }

        var result: [String] = []
        var current = ""

        for sentence in sentences {
            let sentencePieces = splitOversized(
                sentence.trimmingCharacters(in: .whitespacesAndNewlines),
                maxCharacters: maxCharacters
            )

            for piece in sentencePieces where !piece.isEmpty {
                if current.isEmpty {
                    current = piece
                } else if current.count + piece.count + 1 <= maxCharacters {
                    current += " " + piece
                } else {
                    result.append(current)
                    current = piece
                }
            }
        }

        if !current.isEmpty { result.append(current) }
        return result
    }

    private static func splitOversized(_ text: String, maxCharacters: Int) -> [String] {
        guard text.count > maxCharacters else { return text.isEmpty ? [] : [text] }

        var pieces: [String] = []
        var remainder = text[...]

        while remainder.count > maxCharacters {
            let hardEnd = remainder.index(remainder.startIndex, offsetBy: maxCharacters)
            let window = remainder[..<hardEnd]

            let splitIndex: String.Index
            if let whitespace = window.lastIndex(where: { $0.isWhitespace }),
               whitespace != window.startIndex {
                splitIndex = whitespace
            } else {
                splitIndex = hardEnd
            }

            let piece = remainder[..<splitIndex]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if !piece.isEmpty { pieces.append(piece) }

            remainder = remainder[splitIndex...]
            while let first = remainder.first, first.isWhitespace {
                remainder.removeFirst()
            }
        }

        let finalPiece = remainder.trimmingCharacters(in: .whitespacesAndNewlines)
        if !finalPiece.isEmpty { pieces.append(finalPiece) }
        return pieces
    }
}

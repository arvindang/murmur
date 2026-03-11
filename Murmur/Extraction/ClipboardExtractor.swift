import AppKit

enum ClipboardExtractor {

    static func extractText(maxLength: Int = 10_000) -> String? {
        let pasteboard = NSPasteboard.general

        // Try plain string first
        if let text = pasteboard.string(forType: .string) {
            return clean(text, maxLength: maxLength)
        }

        // Try HTML content, convert to plain text
        if let html = pasteboard.string(forType: .html) {
            return clean(stripHTML(html), maxLength: maxLength)
        }

        // Try RTF
        if let rtfData = pasteboard.data(forType: .rtf),
           let attributed = try? NSAttributedString(
               data: rtfData,
               options: [.documentType: NSAttributedString.DocumentType.rtf],
               documentAttributes: nil
           ) {
            return clean(attributed.string, maxLength: maxLength)
        }

        return nil
    }

    // MARK: - Private

    private static func clean(_ text: String, maxLength: Int) -> String? {
        var cleaned = text
            .components(separatedBy: .newlines)
            .map { $0.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression) }
            .joined(separator: "\n")

        // Collapse 3+ blank lines to double
        cleaned = cleaned.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)

        cleaned = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !cleaned.isEmpty else { return nil }

        if cleaned.count > maxLength {
            let truncated = String(cleaned.prefix(maxLength))
            if let lastSentenceEnd = truncated.lastIndex(where: { ".!?".contains($0) }) {
                return String(truncated[...lastSentenceEnd])
            }
            return truncated + "..."
        }

        return cleaned
    }

    private static func stripHTML(_ html: String) -> String {
        guard let data = html.data(using: .utf8),
              let attributed = try? NSAttributedString(
                  data: data,
                  options: [
                      .documentType: NSAttributedString.DocumentType.html,
                      .characterEncoding: String.Encoding.utf8.rawValue,
                  ],
                  documentAttributes: nil
              )
        else {
            // Fallback: regex tag stripping
            return html
                .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
                .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return attributed.string
    }
}

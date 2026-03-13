import Foundation
import SwiftReadability

enum ReadabilityExtractor {

    /// Fetches HTML from a URL and extracts readable text content using Mozilla's Readability algorithm.
    static func extract(from url: URL, maxLength: Int = 10_000) async -> String? {
        guard let scheme = url.scheme, ["http", "https"].contains(scheme) else { return nil }

        // Skip non-HTML resources
        let pathExtension = url.pathExtension.lowercased()
        let nonHTMLExtensions = ["pdf", "png", "jpg", "jpeg", "gif", "svg", "mp3", "mp4", "zip", "dmg"]
        if nonHTMLExtensions.contains(pathExtension) { return nil }

        // Fetch HTML with timeout and browser-like User-Agent
        var request = URLRequest(url: url, timeoutInterval: 5)
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15",
            forHTTPHeaderField: "User-Agent"
        )

        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode),
              let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type"),
              contentType.contains("text/html") || contentType.contains("application/xhtml"),
              let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1)
        else {
            return nil
        }

        // Parse with Readability (skip isProbablyReaderable to avoid double-parsing the DOM)
        let reader = Readability(html: html, url: url)
        guard let result = try? reader.parse() else { return nil }
        let textContent = result.textContent
        guard !textContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

        // Clean and validate minimum length
        guard let cleaned = ClipboardExtractor.clean(textContent, maxLength: maxLength),
              cleaned.count >= 50
        else {
            return nil
        }

        return cleaned
    }
}

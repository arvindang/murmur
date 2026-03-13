import AppKit
import AXorcist

@MainActor
enum AccessibilityExtractor {

    static var hasPermission: Bool {
        AXPermissionHelpers.hasAccessibilityPermissions()
    }

    static func requestPermission() {
        AXPermissionHelpers.askForAccessibilityIfNeeded()
    }

    static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }

    /// Main entry point: tries selected text -> focused text -> document text.
    static func extractText(maxLength: Int = 10_000) -> ExtractionResult? {
        guard hasPermission else { return nil }

        let frontmostApp = NSWorkspace.shared.frontmostApplication
        let appName = frontmostApp?.localizedName
        let bundleId = frontmostApp?.bundleIdentifier

        guard let app = Element.focusedApplication(),
              let focused = app.focusedUIElement() else {
            return nil
        }

        // Strategy 1: Selected text (fastest, most intentional)
        if let selected = focused.selectedText(),
           let result = makeResult(selected, appName: appName, bundleId: bundleId, maxLength: maxLength) {
            return result
        }

        // Strategy 2: Focused element value (stringValue already tries AXValue internally)
        if let value = focused.stringValue(),
           let result = makeResult(value, appName: appName, bundleId: bundleId, maxLength: maxLength) {
            return result
        }

        // Strategy 3: Walk children for text content (web areas, static text)
        if let documentText = extractDocumentText(from: app, maxLength: maxLength, maxDepth: 10) {
            return ExtractionResult(
                text: documentText,
                source: .accessibility,
                appName: appName,
                contentHint: detectContentHint(bundleId: bundleId, text: documentText)
            )
        }

        return nil
    }

    // MARK: - Private Helpers

    private static func makeResult(_ rawText: String, appName: String?, bundleId: String?, maxLength: Int) -> ExtractionResult? {
        guard !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let cleaned = ClipboardExtractor.clean(rawText, maxLength: maxLength) else {
            return nil
        }
        return ExtractionResult(
            text: cleaned,
            source: .accessibility,
            appName: appName,
            contentHint: detectContentHint(bundleId: bundleId, text: cleaned)
        )
    }

    // MARK: - Document Text Extraction

    private static let textRoles: Set<String> = ["AXTextArea", "AXTextField", "AXStaticText"]
    private static let noisyRoleDescriptions: Set<String> = ["navigation", "banner", "contentinfo", "complementary", "footer", "nav"]
    private static let maxNodeVisits = 500 // Increased for deeper web trees

    private static func extractDocumentText(from app: Element, maxLength: Int, maxDepth: Int) -> String? {
        guard let window = app.focusedWindow() else { return nil }

        var collected: [String] = []
        var nodesVisited = 0

        // Try to find a 'main' landmark first for a very targeted extraction
        if let mainLandmark = findMainLandmark(in: window) {
            collectText(from: mainLandmark, into: &collected, maxDepth: maxDepth, currentDepth: 0, nodesVisited: &nodesVisited)
        } else {
            collectText(from: window, into: &collected, maxDepth: maxDepth, currentDepth: 0, nodesVisited: &nodesVisited)
        }

        let joined = collected.joined(separator: "\n")
        guard !joined.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

        return ClipboardExtractor.clean(joined, maxLength: maxLength)
    }

    private static func findMainLandmark(in element: Element) -> Element? {
        if let desc = element.roleDescription(),
           desc.lowercased() == "main" {
            return element
        }

        guard let children = element.children() else { return nil }
        for child in children {
            if let found = findMainLandmark(in: child) {
                return found
            }
        }
        return nil
    }

    private static func collectText(from element: Element, into texts: inout [String], maxDepth: Int, currentDepth: Int, nodesVisited: inout Int) {
        guard currentDepth < maxDepth, nodesVisited < maxNodeVisits else { return }
        nodesVisited += 1

        let role = element.role() ?? ""

        // Skip noisy areas like navigation, footer, etc.
        if let desc = element.roleDescription() {
            if noisyRoleDescriptions.contains(desc.lowercased()) {
                return
            }
        }

        if textRoles.contains(role) {
            if let value = element.stringValue(),
               !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                texts.append(value)
                return
            }
        }

        guard let children = element.children() else { return }
        for child in children {
            guard nodesVisited < maxNodeVisits else { return }
            collectText(from: child, into: &texts, maxDepth: maxDepth, currentDepth: currentDepth + 1, nodesVisited: &nodesVisited)
        }
    }

    // MARK: - Content Hint Detection

    private static let emailBundleIds: Set<String> = ["com.apple.mail", "com.microsoft.Outlook"]
    private static let codeBundleIds: Set<String> = ["com.apple.dt.Xcode", "com.microsoft.VSCode", "com.sublimetext.4", "com.jetbrains.intellij"]
    private static let chatBundleIds: Set<String> = ["com.tinyspeck.slackmacgap", "com.hnc.Discord", "com.apple.MobileSMS"]

    // Indicators that are unambiguously code (not common English)
    private static let strongCodeIndicators = ["func ", "def ", "();", "=>", "{{", "}}", "import ", "const "]
    // Indicators that could appear in English but suggest code in combination
    private static let weakCodeIndicators = ["let ", "var ", "return ", "class ", "if (", "for (", "while (", "->"]
    private static let emailIndicators = ["From:", "To:", "Subject:", "Dear ", "Regards,", "Sincerely,"]

    static func detectContentHint(bundleId: String?, text: String) -> ContentHint {
        if let bundleId {
            if emailBundleIds.contains(bundleId) { return .email }
            if codeBundleIds.contains(bundleId) { return .code }
            if chatBundleIds.contains(bundleId) { return .chat }
        }

        // Text-based heuristics (scan prefix only for performance)
        let scanText = text.count > 2000 ? String(text.prefix(2000)) : text

        let strongScore = strongCodeIndicators.reduce(0) { $0 + (scanText.contains($1) ? 1 : 0) }
        let weakScore = weakCodeIndicators.reduce(0) { $0 + (scanText.contains($1) ? 1 : 0) }
        // Require at least one strong indicator, total >= 3
        if strongScore >= 1 && (strongScore + weakScore) >= 3 {
            return .code
        }

        let emailScore = emailIndicators.reduce(0) { $0 + (scanText.contains($1) ? 1 : 0) }
        if emailScore >= 2 {
            return .email
        }

        if text.count > 500 {
            return .article
        }

        return .unknown
    }
}

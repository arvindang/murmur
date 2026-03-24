import AppKit
import AXorcist
import os.log

private let logger = Logger(subsystem: "com.murmur.app", category: "BrowserExtractor")

@MainActor
enum BrowserExtractor {

    // MARK: - Supported Browsers

    private static let supportedBrowsers: Set<String> = [
        "com.apple.Safari",
        "com.apple.SafariTechnologyPreview",
        "com.google.Chrome",
        "com.google.Chrome.canary",
        "company.thebrowser.Browser",
        "com.microsoft.edgemac",
        "com.brave.Browser",
        "com.vivaldi.Vivaldi",
        "com.operasoftware.Opera",
        "org.mozilla.firefox",
        "org.mozilla.firefoxdeveloperedition",
    ]

    static func isBrowser(bundleId: String) -> Bool {
        supportedBrowsers.contains(bundleId)
    }

    // MARK: - Extraction (async 3-tier pipeline)

    static func extractText(bundleId: String, appName: String?, maxLength: Int = 10_000) async -> ExtractionResult? {
        guard supportedBrowsers.contains(bundleId) else { return nil }

        // Tier 1: Selected text via Accessibility API (instant, works in all browsers)
        if let result = extractSelectedText(bundleId: bundleId, appName: appName, maxLength: maxLength) {
            return result
        }

        // Tier 2: URL-fetch + Readability (no JS permission needed)
        if let url = extractURL(bundleId: bundleId),
           let text = await ReadabilityExtractor.extract(from: url, maxLength: maxLength) {
            return makeResult(text: text, bundleId: bundleId, appName: appName)
        }

        // Tier 3: JS injection fallback (requires browser-specific JS permission)
        if let result = extractViaJavaScript(bundleId: bundleId, appName: appName, maxLength: maxLength) {
            return result
        }

        return nil
    }

    // MARK: - Tier 1: Selected Text via AX API

    private static func extractSelectedText(bundleId: String, appName: String?, maxLength: Int) -> ExtractionResult? {
        guard AccessibilityExtractor.hasPermission,
              let app = Element.focusedApplication(),
              let focused = app.focusedUIElement(),
              let selected = focused.selectedText(),
              !selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let cleaned = ClipboardExtractor.clean(selected, maxLength: maxLength)
        else {
            return nil
        }

        return makeResult(text: cleaned, bundleId: bundleId, appName: appName)
    }

    // MARK: - Tier 2: URL Extraction via AppleScript

    private static func extractURL(bundleId: String) -> URL? {
        let name = scriptAppName(for: bundleId)
        let script: String

        if isSafari(bundleId) {
            script = """
            tell application "\(name)"
                if (count documents) > 0 then
                    return URL of front document
                end if
            end tell
            """
        } else {
            // Chrome-family and Firefox both use the same AppleScript
            script = """
            tell application "\(name)"
                if (count windows) > 0 then
                    return URL of active tab of front window
                end if
            end tell
            """
        }

        guard let result = runAppleScript(script, context: "URL extraction", bundleId: bundleId) else {
            return nil
        }
        return URL(string: result)
    }

    // MARK: - Tier 3: JS Injection Fallback

    private static func extractViaJavaScript(bundleId: String, appName: String?, maxLength: Int) -> ExtractionResult? {
        // Firefox doesn't support JS injection via AppleScript
        guard !isFirefox(bundleId) else { return nil }

        let script = buildJSAppleScript(js: extractionJS(), bundleId: bundleId)

        guard let rawText = runAppleScript(script, context: "JS injection", bundleId: bundleId),
              !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let cleaned = ClipboardExtractor.clean(rawText, maxLength: maxLength)
        else {
            return nil
        }

        return makeResult(text: cleaned, bundleId: bundleId, appName: appName)
    }

    // MARK: - Private Helpers

    private static func makeResult(text: String, bundleId: String, appName: String?) -> ExtractionResult {
        let contentHint = AccessibilityExtractor.detectContentHint(bundleId: bundleId, text: text)
        return ExtractionResult(
            text: text,
            source: .accessibility,
            appName: appName,
            contentHint: contentHint
        )
    }

    private static func runAppleScript(_ script: String, context: String, bundleId: String) -> String? {
        guard let nsScript = NSAppleScript(source: script) else { return nil }
        var error: NSDictionary?
        let result = nsScript.executeAndReturnError(&error)

        if let error {
            logger.warning("\(context) failed for \(bundleId): \(error)")
            return nil
        }

        return result.stringValue
    }

    private static func isSafari(_ bundleId: String) -> Bool {
        bundleId.hasPrefix("com.apple.Safari")
    }

    private static func isFirefox(_ bundleId: String) -> Bool {
        bundleId.hasPrefix("org.mozilla.firefox")
    }

    private static func scriptAppName(for bundleId: String) -> String {
        switch bundleId {
        case "com.apple.Safari":
            return "Safari"
        case "com.apple.SafariTechnologyPreview":
            return "Safari Technology Preview"
        case "com.google.Chrome":
            return "Google Chrome"
        case "com.google.Chrome.canary":
            return "Google Chrome Canary"
        case "company.thebrowser.Browser":
            return "Arc"
        case "com.microsoft.edgemac":
            return "Microsoft Edge"
        case "com.brave.Browser":
            return "Brave Browser"
        case "com.vivaldi.Vivaldi":
            return "Vivaldi"
        case "com.operasoftware.Opera":
            return "Opera"
        case "org.mozilla.firefox":
            return "Firefox"
        case "org.mozilla.firefoxdeveloperedition":
            return "Firefox Developer Edition"
        default:
            return "Safari"
        }
    }

    private static func escapeForAppleScript(_ js: String) -> String {
        js.replacingOccurrences(of: "\\", with: "\\\\")
          .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func buildJSAppleScript(js: String, bundleId: String) -> String {
        let name = scriptAppName(for: bundleId)
        let escaped = escapeForAppleScript(js)

        if isSafari(bundleId) {
            return """
            tell application "\(name)"
                if (count documents) > 0 then
                    do JavaScript "\(escaped)" in front document
                else
                    return ""
                end if
            end tell
            """
        } else {
            // Chrome-based (Chrome, Arc, Edge, Brave, Vivaldi, Opera)
            return """
            tell application "\(name)"
                if (count windows) > 0 then
                    tell active tab of front window
                        execute javascript "\(escaped)"
                    end tell
                else
                    return ""
                end if
            end tell
            """
        }
    }

    private static func extractionJS() -> String {
        """
        (function() {
            // 1. If user has selected text, read that first
            var sel = window.getSelection().toString().trim();
            if (sel.length > 0) return sel;

            // 2. Look for common main content containers
            var selectors = [
                'article',
                'main',
                '[role="main"]',
                '#Main',       // Daring Fireball
                '#content',
                '.post-content',
                '.article-body',
                '.entry-content',
                '.entry'       // Daring Fireball / older blogs
            ];

            for (var i = 0; i < selectors.length; i++) {
                var el = document.querySelector(selectors[i]);
                if (el && el.innerText.trim().length > 200) {
                    return el.innerText;
                }
            }

            // 3. Heuristic: find the div/section with the most paragraph text
            var best = null, bestLen = 0;
            document.querySelectorAll('div, section').forEach(function(d) {
                var pText = Array.from(d.querySelectorAll('p'))
                                .map(function(p) { return p.innerText; })
                                .join(' ');
                if (pText.length > bestLen) { best = d; bestLen = pText.length; }
            });

            if (best && bestLen > 200) return best.innerText;

            // 4. Fallback to full body if nothing better found
            return document.body.innerText;
        })()
        """
    }
}

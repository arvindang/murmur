import AppKit

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
    ]

    static func isBrowser(bundleId: String) -> Bool {
        supportedBrowsers.contains(bundleId)
    }

    // MARK: - Extraction

    static func extractText(bundleId: String, appName: String?, maxLength: Int = 10_000) -> ExtractionResult? {
        guard supportedBrowsers.contains(bundleId) else { return nil }

        let script = buildAppleScript(js: extractionJS(), bundleId: bundleId)
        guard let nsScript = NSAppleScript(source: script) else { return nil }

        var error: NSDictionary?
        let result = nsScript.executeAndReturnError(&error)

        guard error == nil,
              let rawText = result.stringValue,
              !rawText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let cleaned = ClipboardExtractor.clean(rawText, maxLength: maxLength)
        else {
            return nil
        }

        let contentHint = AccessibilityExtractor.detectContentHint(bundleId: bundleId, text: cleaned)

        return ExtractionResult(
            text: cleaned,
            source: .accessibility,
            appName: appName,
            contentHint: contentHint
        )
    }

    // MARK: - Private

    private static func isSafari(_ bundleId: String) -> Bool {
        bundleId.hasPrefix("com.apple.Safari")
    }

    private static func scriptAppName(for bundleId: String) -> String {
        switch bundleId {
        case "com.apple.Safari", "com.apple.SafariTechnologyPreview":
            return "Safari"
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
        default:
            return "Safari"
        }
    }

    private static func escapeForAppleScript(_ js: String) -> String {
        js.replacingOccurrences(of: "\\", with: "\\\\")
          .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func buildAppleScript(js: String, bundleId: String) -> String {
        let name = scriptAppName(for: bundleId)
        let escaped = escapeForAppleScript(js)
        let command = isSafari(bundleId)
            ? "do JavaScript \"\(escaped)\" in front document"
            : "execute front window's active tab javascript \"\(escaped)\""
        return """
        tell application "\(name)"
            \(command)
        end tell
        """
    }

    private static func extractionJS() -> String {
        """
        (function() {
            var sel = window.getSelection().toString().trim();
            if (sel.length > 0) return sel;

            var el = document.querySelector('article')
                  || document.querySelector('[role="main"]')
                  || document.querySelector('main');
            if (el) return el.innerText;

            var best = null, bestLen = 0;
            document.querySelectorAll('div, section').forEach(function(d) {
                var pText = Array.from(d.querySelectorAll('p'))
                                .map(function(p) { return p.innerText; })
                                .join(' ');
                if (pText.length > bestLen) { best = d; bestLen = pText.length; }
            });
            if (best && bestLen > 100) return best.innerText;

            return document.body.innerText;
        })()
        """
    }
}

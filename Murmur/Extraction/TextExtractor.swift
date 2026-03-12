import Foundation
import Defaults

struct ExtractionResult: Sendable {
    let text: String
    let source: TextSource
    let appName: String?
    let contentHint: ContentHint?

    var estimatedReadingTime: TimeInterval {
        // ~5 chars per word average, 150 wpm reading speed
        Double(text.count) / 5.0 / 150.0 * 60.0
    }

    var readingTimeDescription: String {
        let seconds = estimatedReadingTime
        if seconds < 60 {
            return "< 1 min"
        }
        let minutes = Int(ceil(seconds / 60.0))
        return "\(minutes) min"
    }
}

enum TextSource: String, Defaults.Serializable, CaseIterable, Sendable {
    case auto
    case accessibility
    case clipboard

    var displayName: String {
        switch self {
        case .auto: "Auto"
        case .accessibility: "Accessibility"
        case .clipboard: "Clipboard"
        }
    }
}

enum ContentHint: Sendable {
    case article
    case email
    case code
    case chat
    case unknown

    var label: String {
        switch self {
        case .article: "article"
        case .email: "email"
        case .code: "code"
        case .chat: "chat"
        case .unknown: "text"
        }
    }
}

import Foundation

// MARK: - Types

enum PlaybackState: Sendable {
    case idle
    case speaking
    case paused
}

struct VoiceInfo: Identifiable, Sendable, Hashable {
    let id: String
    let name: String
    let language: String
    let quality: Quality
    let group: String?

    init(id: String, name: String, language: String, quality: Quality, group: String? = nil) {
        self.id = id
        self.name = name
        self.language = language
        self.quality = quality
        self.group = group
    }

    enum Quality: Int, Sendable, Comparable {
        case standard = 0
        case enhanced = 1
        case premium = 2

        static func < (lhs: Quality, rhs: Quality) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }
}

// MARK: - Protocol

@MainActor
protocol VoiceEngine: AnyObject {
    var playbackState: PlaybackState { get }
    var onStateChange: ((PlaybackState) -> Void)? { get set }
    var onError: ((String) -> Void)? { get set }

    func speak(_ text: String)
    func pause()
    func resume()
    func stop()

    var availableVoices: [VoiceInfo] { get }
    var selectedVoiceId: String? { get set }
    var rate: Float { get set }
}

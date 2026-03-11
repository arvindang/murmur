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

    enum Quality: String, Sendable, Comparable {
        case standard
        case enhanced
        case premium

        static func < (lhs: Quality, rhs: Quality) -> Bool {
            let order: [Quality] = [.standard, .enhanced, .premium]
            return order.firstIndex(of: lhs)! < order.firstIndex(of: rhs)!
        }
    }
}

// MARK: - Protocol

@MainActor
protocol VoiceEngine: AnyObject {
    var playbackState: PlaybackState { get }
    var onStateChange: ((PlaybackState) -> Void)? { get set }

    func speak(_ text: String)
    func pause()
    func resume()
    func stop()

    var availableVoices: [VoiceInfo] { get }
    var selectedVoiceId: String? { get set }
    var rate: Float { get set }
}

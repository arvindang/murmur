import Foundation
import Defaults
import KeyboardShortcuts

// MARK: - Global Hotkeys

extension KeyboardShortcuts.Name {
    static let readAloud = Self("readAloud", default: .init(.l, modifiers: [.command, .shift]))
}

// MARK: - Voice Engine Type

enum VoiceEngineType: String, Defaults.Serializable, CaseIterable, Sendable {
    case system
    case openai
}

// MARK: - User Defaults

extension Defaults.Keys {
    static let selectedVoiceId = Key<String>("selectedVoiceId", default: "")
    static let speakingRate = Key<Double>("speakingRate", default: 1.0)
    static let maxTextLength = Key<Int>("maxTextLength", default: 10_000)
    static let voiceEngineType = Key<VoiceEngineType>("voiceEngineType", default: .system)
    static let openaiVoiceId = Key<String>("openaiVoiceId", default: "nova")
    static let textSource = Key<TextSource>("textSource", default: .auto)
}

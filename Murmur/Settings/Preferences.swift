import Foundation
import Defaults
import KeyboardShortcuts

// MARK: - Global Hotkeys

extension KeyboardShortcuts.Name {
    static let readAloud = Self("readAloud", default: .init(.l, modifiers: [.command, .shift]))
}

// MARK: - User Defaults

extension Defaults.Keys {
    static let selectedVoiceId = Key<String>("selectedVoiceId", default: "")
    static let speakingRate = Key<Double>("speakingRate", default: 1.0)
    static let maxTextLength = Key<Int>("maxTextLength", default: 10_000)
}

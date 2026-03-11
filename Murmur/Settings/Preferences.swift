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
    case murmur
}

// MARK: - Murmur Model

enum MurmurModel: String, Defaults.Serializable, CaseIterable, Sendable {
    case soprano
    case marvis
    case qwen3tts

    var displayName: String {
        switch self {
        case .soprano: "Soprano"
        case .marvis: "Marvis TTS"
        case .qwen3tts: "Qwen3-TTS"
        }
    }

    var modelRepo: String {
        switch self {
        case .soprano: "mlx-community/Soprano-80M-bf16"
        case .marvis: "Marvis-AI/marvis-tts-250m-v0.2-MLX-8bit"
        case .qwen3tts: "mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit"
        }
    }

    var modelType: String {
        switch self {
        case .soprano: "soprano"
        case .marvis: "csm"
        case .qwen3tts: "qwen3_tts"
        }
    }

    var approxSize: String {
        switch self {
        case .soprano: "~160 MB"
        case .marvis: "~250 MB"
        case .qwen3tts: "~500 MB"
        }
    }

    var supportedLanguages: [String] {
        switch self {
        case .soprano: ["English"]
        case .marvis: ["English", "French", "German"]
        case .qwen3tts: ["English", "Chinese", "Japanese", "Korean", "German", "French", "Russian", "Portuguese", "Spanish", "Italian"]
        }
    }

    var dropdownLabel: String {
        let langs = supportedLanguages.count <= 3
            ? supportedLanguages.joined(separator: ", ")
            : "\(supportedLanguages.count) languages"
        return "\(displayName) — \(langs) (\(approxSize))"
    }

    var defaultVoices: [VoiceInfo] {
        switch self {
        case .soprano:
            [VoiceInfo(id: "default", name: "Soprano", language: "English", quality: .premium)]
        case .marvis:
            [
                VoiceInfo(id: "conversational_a", name: "Conversational A", language: "English", quality: .premium),
                VoiceInfo(id: "conversational_b", name: "Conversational B", language: "English", quality: .premium),
                VoiceInfo(id: "conversational_c", name: "Conversational C", language: "French", quality: .premium),
                VoiceInfo(id: "conversational_d", name: "Conversational D", language: "German", quality: .premium),
            ]
        case .qwen3tts:
            [VoiceInfo(id: "default", name: "Qwen3-TTS", language: "Auto-detect", quality: .premium)]
        }
    }
}

// MARK: - User Defaults

extension Defaults.Keys {
    static let selectedVoiceId = Key<String>("selectedVoiceId", default: "")
    static let speakingRate = Key<Double>("speakingRate", default: 1.0)
    static let maxTextLength = Key<Int>("maxTextLength", default: 10_000)
    static let voiceEngineType = Key<VoiceEngineType>("voiceEngineType", default: .system)
    static let murmurModel = Key<MurmurModel>("murmurModel", default: .soprano)
    static let murmurVoiceId = Key<String>("murmurVoiceId", default: "default")
}

import AVFoundation

@MainActor
final class SystemVoiceEngine: NSObject, VoiceEngine {

    private let synthesizer = AVSpeechSynthesizer()
    private var activeUtterances: [AVSpeechUtterance] = []

    private(set) var playbackState: PlaybackState = .idle
    var onStateChange: ((PlaybackState) -> Void)?
    var onError: ((String) -> Void)?
    var selectedVoiceId: String?
    var rate: Float = AVSpeechUtteranceDefaultSpeechRate

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String) {
        let chunks = SpeechTextChunker.chunks(for: text, maxCharacters: 3_000)
        guard !chunks.isEmpty else { return }

        stop()
        setPlaybackState(.speaking)

        activeUtterances = chunks.map { chunk in
            let utterance = AVSpeechUtterance(string: chunk)

            if let voiceId = selectedVoiceId {
                utterance.voice = AVSpeechSynthesisVoice(identifier: voiceId)
            } else {
                utterance.voice = Self.bestAvailableVoice()
            }

            utterance.rate = rate
            utterance.pitchMultiplier = 1.0
            utterance.volume = 1.0
            return utterance
        }

        for utterance in activeUtterances {
            synthesizer.speak(utterance)
        }
    }

    func pause() {
        guard playbackState == .speaking else { return }
        if synthesizer.pauseSpeaking(at: .word) {
            setPlaybackState(.paused)
        }
    }

    func resume() {
        guard playbackState == .paused else { return }
        if synthesizer.continueSpeaking() {
            setPlaybackState(.speaking)
        }
    }

    func stop() {
        guard playbackState != .idle || !activeUtterances.isEmpty else { return }
        activeUtterances.removeAll()
        synthesizer.stopSpeaking(at: .immediate)
        setPlaybackState(.idle)
    }

    private(set) lazy var availableVoices: [VoiceInfo] = {
        Self.englishVoices()
            .map { voice in
                VoiceInfo(
                    id: voice.identifier,
                    name: voice.name,
                    language: Locale.current.localizedString(forIdentifier: voice.language) ?? voice.language,
                    quality: Self.mapQuality(voice.quality)
                )
            }
            .sorted { lhs, rhs in
                if lhs.quality != rhs.quality {
                    return lhs.quality > rhs.quality
                }
                return lhs.name < rhs.name
            }
    }()

    // MARK: - Private

    private func setPlaybackState(_ state: PlaybackState) {
        playbackState = state
        onStateChange?(state)
    }

    private static func englishVoices() -> [AVSpeechSynthesisVoice] {
        AVSpeechSynthesisVoice.speechVoices()
            .filter { $0.language.hasPrefix("en") }
    }

    private static func bestAvailableVoice() -> AVSpeechSynthesisVoice? {
        englishVoices()
            .sorted { $0.quality.rawValue > $1.quality.rawValue }
            .first
    }

    private static func mapQuality(_ quality: AVSpeechSynthesisVoiceQuality) -> VoiceInfo.Quality {
        switch quality {
        case .premium: .premium
        case .enhanced: .enhanced
        default: .standard
        }
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension SystemVoiceEngine: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didFinish utterance: AVSpeechUtterance
    ) {
        let utteranceId = ObjectIdentifier(utterance)
        MainActor.assumeIsolated {
            guard let index = activeUtterances.firstIndex(where: {
                ObjectIdentifier($0) == utteranceId
            }) else {
                return
            }
            activeUtterances.remove(at: index)
            if activeUtterances.isEmpty {
                setPlaybackState(.idle)
            }
        }
    }

    nonisolated func speechSynthesizer(
        _ synthesizer: AVSpeechSynthesizer,
        didCancel utterance: AVSpeechUtterance
    ) {
        let utteranceId = ObjectIdentifier(utterance)
        MainActor.assumeIsolated {
            guard let index = activeUtterances.firstIndex(where: {
                ObjectIdentifier($0) == utteranceId
            }) else {
                return
            }
            activeUtterances.remove(at: index)
            if activeUtterances.isEmpty {
                setPlaybackState(.idle)
            }
        }
    }
}

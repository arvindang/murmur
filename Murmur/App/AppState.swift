import SwiftUI
import AVFoundation
import KeyboardShortcuts
import Defaults

@MainActor
@Observable
final class AppState {

    private(set) var playbackState: PlaybackState = .idle
    var statusMessage: String?

    private var activeEngine: any VoiceEngine
    let modelManager = ModelManager()

    var currentEngineType: VoiceEngineType {
        Defaults[.voiceEngineType]
    }

    init() {
        let engineType = Defaults[.voiceEngineType]
        if engineType == .murmur {
            let model = Defaults[.murmurModel]
            activeEngine = MLXTTSEngine(model: model)
        } else {
            activeEngine = SystemVoiceEngine()
        }
        setupVoiceEngine()
        setupHotkeys()

        // Migrate legacy .soprano preference to .murmur
        if let raw = UserDefaults.standard.string(forKey: "voiceEngineType"), raw == "soprano" {
            Defaults[.voiceEngineType] = .murmur
            Defaults[.murmurModel] = .soprano
        }
    }

    // MARK: - Actions

    func toggleReadAloud() {
        switch playbackState {
        case .idle:
            readClipboard()
        case .speaking:
            activeEngine.stop()
        case .paused:
            activeEngine.resume()
        }
    }

    func readClipboard() {
        let maxLength = Defaults[.maxTextLength]
        guard let text = ClipboardExtractor.extractText(maxLength: maxLength) else {
            statusMessage = "No text in clipboard"
            return
        }

        let engineType = Defaults[.voiceEngineType]
        if engineType == .murmur {
            let model = Defaults[.murmurModel]
            if modelManager.state(for: model) != .downloaded {
                statusMessage = "\(model.displayName) model not downloaded — open Settings to download"
                return
            }
        }

        statusMessage = nil
        configureActiveEngine()
        activeEngine.speak(text)
    }

    func pausePlayback() {
        activeEngine.pause()
    }

    func resumePlayback() {
        activeEngine.resume()
    }

    func stopPlayback() {
        activeEngine.stop()
    }

    func previewVoice(id: String) {
        configureActiveEngine(voiceOverride: id)
        activeEngine.speak("Hello! This is how I sound. I'm Murmur, your reading assistant.")
    }

    func deleteModel(_ model: MurmurModel) {
        activeEngine.stop()
        modelManager.deleteModel(model)
        // If we deleted the currently selected murmur model, switch to system
        if Defaults[.murmurModel] == model {
            switchEngine(to: .system)
        }
    }

    func switchEngine(to type: VoiceEngineType) {
        activeEngine.stop()
        Defaults[.voiceEngineType] = type

        switch type {
        case .system:
            activeEngine = SystemVoiceEngine()
        case .murmur:
            let model = Defaults[.murmurModel]
            activeEngine = MLXTTSEngine(model: model)
        }

        setupVoiceEngine()
    }

    func switchMurmurModel(to model: MurmurModel) {
        guard model != Defaults[.murmurModel] else { return }
        activeEngine.stop()
        Defaults[.murmurModel] = model
        Defaults[.murmurVoiceId] = model.defaultVoices.first?.id ?? "default"
        activeEngine = MLXTTSEngine(model: model)
        setupVoiceEngine()
    }

    // MARK: - Computed

    var menuBarIcon: String {
        switch playbackState {
        case .idle: "waveform"
        case .speaking: "waveform.circle.fill"
        case .paused: "pause.circle"
        }
    }

    var availableVoices: [VoiceInfo] {
        activeEngine.availableVoices
    }

    // MARK: - Private

    private func setupVoiceEngine() {
        activeEngine.onStateChange = { [weak self] state in
            self?.playbackState = state
        }
    }

    private func setupHotkeys() {
        KeyboardShortcuts.onKeyUp(for: .readAloud) { [weak self] in
            Task { @MainActor in
                self?.toggleReadAloud()
            }
        }
    }

    private func configureActiveEngine(voiceOverride: String? = nil) {
        let engineType = Defaults[.voiceEngineType]
        switch engineType {
        case .system:
            activeEngine.rate = Self.avSpeechRate(from: Defaults[.speakingRate])
            let voiceId = voiceOverride ?? Defaults[.selectedVoiceId]
            activeEngine.selectedVoiceId = voiceId.isEmpty ? nil : voiceId
        case .murmur:
            activeEngine.rate = Float(Defaults[.speakingRate])
            let voiceId = voiceOverride ?? Defaults[.murmurVoiceId]
            activeEngine.selectedVoiceId = voiceId.isEmpty ? nil : voiceId
        }
    }

    /// Maps user-facing rate (0.5-2.0) to AVSpeechSynthesizer rate.
    private static func avSpeechRate(from userRate: Double) -> Float {
        Float(userRate) * AVSpeechUtteranceDefaultSpeechRate
    }
}

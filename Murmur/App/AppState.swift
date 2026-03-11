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
        if engineType == .soprano {
            activeEngine = SopranoEngine()
        } else {
            activeEngine = SystemVoiceEngine()
        }
        setupVoiceEngine()
        setupHotkeys()
        modelManager.checkModelAvailability()
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
        if engineType == .soprano && modelManager.sopranoModelState != .downloaded {
            statusMessage = "Soprano model not downloaded — open Settings to download"
            return
        }

        statusMessage = nil

        switch engineType {
        case .system:
            activeEngine.rate = Self.avSpeechRate(from: Defaults[.speakingRate])
            let voiceId = Defaults[.selectedVoiceId]
            activeEngine.selectedVoiceId = voiceId.isEmpty ? nil : voiceId
        case .soprano:
            activeEngine.rate = Float(Defaults[.speakingRate])
            activeEngine.selectedVoiceId = nil
        }

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
        let engineType = Defaults[.voiceEngineType]
        if engineType == .system {
            activeEngine.selectedVoiceId = id.isEmpty ? nil : id
            activeEngine.rate = Self.avSpeechRate(from: Defaults[.speakingRate])
        } else {
            activeEngine.selectedVoiceId = nil
            activeEngine.rate = Float(Defaults[.speakingRate])
        }
        activeEngine.speak("Hello! This is how I sound. I'm Murmur, your reading assistant.")
    }

    func switchEngine(to type: VoiceEngineType) {
        activeEngine.stop()
        Defaults[.voiceEngineType] = type

        switch type {
        case .system:
            activeEngine = SystemVoiceEngine()
        case .soprano:
            activeEngine = SopranoEngine()
        }

        setupVoiceEngine()
    }

    static var isOpeningSettings = false

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

    /// Maps user-facing rate (0.5-2.0) to AVSpeechSynthesizer rate.
    private static func avSpeechRate(from userRate: Double) -> Float {
        Float(userRate) * AVSpeechUtteranceDefaultSpeechRate
    }
}

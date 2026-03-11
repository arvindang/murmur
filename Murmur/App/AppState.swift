import SwiftUI
import AVFoundation
import KeyboardShortcuts
import Defaults

@MainActor
@Observable
final class AppState {

    private(set) var playbackState: PlaybackState = .idle
    var statusMessage: String?

    private let voiceEngine = SystemVoiceEngine()

    init() {
        setupVoiceEngine()
        setupHotkeys()
    }

    // MARK: - Actions

    func toggleReadAloud() {
        switch playbackState {
        case .idle:
            readClipboard()
        case .speaking:
            voiceEngine.stop()
        case .paused:
            voiceEngine.resume()
        }
    }

    func readClipboard() {
        let maxLength = Defaults[.maxTextLength]
        guard let text = ClipboardExtractor.extractText(maxLength: maxLength) else {
            statusMessage = "No text in clipboard"
            return
        }
        statusMessage = nil
        voiceEngine.rate = Self.avSpeechRate(from: Defaults[.speakingRate])
        let voiceId = Defaults[.selectedVoiceId]
        voiceEngine.selectedVoiceId = voiceId.isEmpty ? nil : voiceId
        voiceEngine.speak(text)
    }

    func pausePlayback() {
        voiceEngine.pause()
    }

    func resumePlayback() {
        voiceEngine.resume()
    }

    func stopPlayback() {
        voiceEngine.stop()
    }

    func previewVoice(id: String) {
        voiceEngine.selectedVoiceId = id.isEmpty ? nil : id
        voiceEngine.rate = Self.avSpeechRate(from: Defaults[.speakingRate])
        voiceEngine.speak("Hello! This is how I sound. I'm Murmur, your reading assistant.")
    }

    func openSettings() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
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
        voiceEngine.availableVoices
    }

    // MARK: - Private

    private func setupVoiceEngine() {
        voiceEngine.onStateChange = { [weak self] state in
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

    /// Maps user-facing rate (0.5–2.0) to AVSpeechSynthesizer rate.
    private static func avSpeechRate(from userRate: Double) -> Float {
        Float(userRate) * AVSpeechUtteranceDefaultSpeechRate
    }
}

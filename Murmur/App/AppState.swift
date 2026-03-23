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

    init() {
        // Migrate removed engine types to system
        if let raw = UserDefaults.standard.string(forKey: "voiceEngineType"),
           raw == "murmur" || raw == "soprano" {
            Defaults[.voiceEngineType] = .system
        }

        let engineType = Defaults[.voiceEngineType]
        switch engineType {
        case .system:
            activeEngine = SystemVoiceEngine()
        case .openai:
            activeEngine = OpenAITTSEngine()
        }
        setupVoiceEngine()
        setupHotkeys()
    }

    // MARK: - Actions

    func toggleReadAloud() {
        switch playbackState {
        case .idle:
            readText()
        case .speaking:
            activeEngine.stop()
        case .paused:
            activeEngine.resume()
        }
    }

    func readText() {
        let maxLength = Defaults[.maxTextLength]
        let textSource = Defaults[.textSource]

        let useAX = textSource == .auto || textSource == .accessibility
        let useClipboard = textSource == .auto || textSource == .clipboard

        // Browser path is async (URL fetch + Readability), handle separately
        let app = useAX ? NSWorkspace.shared.frontmostApplication : nil
        let bundleId = app?.bundleIdentifier
        let isBrowser = bundleId.map { BrowserExtractor.isBrowser(bundleId: $0) } ?? false

        if isBrowser {
            statusMessage = "Extracting text..."
            Task {
                var result: ExtractionResult?
                if let bundleId {
                    result = await BrowserExtractor.extractText(bundleId: bundleId, appName: app?.localizedName, maxLength: maxLength)
                }
                // Fall through to AX / clipboard if browser extraction returned nil
                if result == nil {
                    result = (useAX ? AccessibilityExtractor.extractText(maxLength: maxLength) : nil)
                             ?? (useClipboard ? clipboardResult(maxLength: maxLength) : nil)
                }
                guard let result else {
                    statusMessage = "No readable text found"
                    return
                }
                buildStatusAndSpeak(result: result)
            }
            return
        }

        // Non-browser path stays synchronous
        let result: ExtractionResult? =
            (useAX ? AccessibilityExtractor.extractText(maxLength: maxLength) : nil) ??
            (useClipboard ? clipboardResult(maxLength: maxLength) : nil)

        guard let result else {
            statusMessage = textSource == .clipboard ? "No text in clipboard" : "No readable text found"
            return
        }

        buildStatusAndSpeak(result: result)
    }

    private func buildStatusAndSpeak(result: ExtractionResult) {
        var parts: [String] = []
        if let appName = result.appName {
            parts.append("Reading from \(appName)")
        } else if result.source == .clipboard {
            parts.append("Reading clipboard")
        }
        if let hint = result.contentHint, hint != .unknown {
            parts.append(result.readingTimeDescription + " " + hint.label)
        }
        statusMessage = parts.isEmpty ? nil : parts.joined(separator: " — ")

        speakText(result.text)
    }

    private func clipboardResult(maxLength: Int) -> ExtractionResult? {
        guard let text = ClipboardExtractor.extractText(maxLength: maxLength) else { return nil }
        return ExtractionResult(text: text, source: .clipboard, appName: nil, contentHint: nil)
    }

    func readClipboard() {
        let maxLength = Defaults[.maxTextLength]
        guard let text = ClipboardExtractor.extractText(maxLength: maxLength) else {
            statusMessage = "No text in clipboard"
            return
        }
        statusMessage = "Reading clipboard"
        speakText(text)
    }

    private func speakText(_ text: String) {
        let engineType = Defaults[.voiceEngineType]
        if engineType == .openai {
            if !KeychainHelper.hasAPIKey() {
                statusMessage = "No OpenAI API key — add one in Settings"
                return
            }
        }

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

    func switchEngine(to type: VoiceEngineType) {
        activeEngine.stop()
        Defaults[.voiceEngineType] = type

        switch type {
        case .system:
            activeEngine = SystemVoiceEngine()
        case .openai:
            activeEngine = OpenAITTSEngine()
        }

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

    // MARK: - Private

    private func setupVoiceEngine() {
        activeEngine.onStateChange = { [weak self] state in
            self?.playbackState = state
        }
        activeEngine.onError = { [weak self] message in
            self?.statusMessage = "TTS error: \(message)"
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
        case .openai:
            // OpenAI handles speed server-side — rate maps directly (0.5–2.0)
            activeEngine.rate = Float(Defaults[.speakingRate])
            let voiceId = voiceOverride ?? Defaults[.openaiVoiceId]
            activeEngine.selectedVoiceId = voiceId.isEmpty ? nil : voiceId
        }
    }

    /// Maps user-facing rate (0.5-2.0) to AVSpeechSynthesizer rate.
    private static func avSpeechRate(from userRate: Double) -> Float {
        Float(userRate) * AVSpeechUtteranceDefaultSpeechRate
    }
}

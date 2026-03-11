import AVFoundation
import NaturalLanguage
import MLXAudioTTS
import MLXLMCommon

@MainActor
final class MLXTTSEngine: NSObject, VoiceEngine {

    private(set) var playbackState: PlaybackState = .idle
    var onStateChange: ((PlaybackState) -> Void)?
    var selectedVoiceId: String?
    var rate: Float = 1.0

    let modelConfig: MurmurModel
    private var model: (any SpeechGenerationModel)?
    private var generationTask: Task<Void, Never>?
    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var timePitchNode: AVAudioUnitTimePitch?
    private var idleTimer: Timer?

    private static let idleTimeout: TimeInterval = 300 // 5 minutes

    init(model: MurmurModel) {
        self.modelConfig = model
        super.init()
    }

    // MARK: - VoiceEngine

    func speak(_ text: String) {
        stop()
        setPlaybackState(.speaking)
        resetIdleTimer()

        generationTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.ensureModelLoaded()
                let sentences = self.splitIntoSentences(text)
                try self.setupAudioChain()

                for sentence in sentences {
                    if Task.isCancelled { break }
                    let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty else { continue }
                    try await self.synthesizeAndPlay(trimmed)
                }

                if !Task.isCancelled {
                    await self.waitForPlaybackCompletion()
                    self.setPlaybackState(.idle)
                }
            } catch {
                if !Task.isCancelled {
                    self.setPlaybackState(.idle)
                }
            }
            self.startIdleTimer()
        }
    }

    func pause() {
        guard playbackState == .speaking else { return }
        playerNode?.pause()
        setPlaybackState(.paused)
    }

    func resume() {
        guard playbackState == .paused else { return }
        playerNode?.play()
        setPlaybackState(.speaking)
    }

    func stop() {
        generationTask?.cancel()
        generationTask = nil
        playerNode?.stop()
        audioEngine?.stop()
        audioEngine = nil
        playerNode = nil
        timePitchNode = nil
        if playbackState != .idle {
            setPlaybackState(.idle)
        }
    }

    private(set) lazy var availableVoices: [VoiceInfo] = modelConfig.defaultVoices

    // MARK: - Model Management

    private func ensureModelLoaded() async throws {
        if model == nil {
            model = try await TTS.loadModel(
                modelRepo: modelConfig.modelRepo,
                modelType: modelConfig.modelType
            )
        }
    }

    func unloadModel() {
        model = nil
    }

    // MARK: - Audio Chain

    private func setupAudioChain() throws {
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let timePitch = AVAudioUnitTimePitch()

        timePitch.rate = rate

        engine.attach(player)
        engine.attach(timePitch)

        let outputFormat = engine.mainMixerNode.outputFormat(forBus: 0)
        engine.connect(player, to: timePitch, format: outputFormat)
        engine.connect(timePitch, to: engine.mainMixerNode, format: outputFormat)

        try engine.start()
        player.play()

        self.audioEngine = engine
        self.playerNode = player
        self.timePitchNode = timePitch
    }

    // MARK: - Synthesis

    private func synthesizeAndPlay(_ text: String) async throws {
        guard let model, let playerNode, let audioEngine else { return }

        let voice = selectedVoiceId ?? "default"

        let stream = model.generatePCMBufferStream(
            text: text,
            voice: voice,
            refAudio: nil,
            refText: nil,
            language: nil
        )

        let outputFormat = audioEngine.mainMixerNode.outputFormat(forBus: 0)

        for try await buffer in stream {
            if Task.isCancelled { break }

            if buffer.format.sampleRate != outputFormat.sampleRate ||
               buffer.format.channelCount != outputFormat.channelCount {
                if let converted = Self.convertBuffer(buffer, to: outputFormat) {
                    await playerNode.scheduleBuffer(converted)
                }
            } else {
                await playerNode.scheduleBuffer(buffer)
            }
        }
    }

    private static func convertBuffer(_ buffer: AVAudioPCMBuffer, to format: AVAudioFormat) -> AVAudioPCMBuffer? {
        guard let converter = AVAudioConverter(from: buffer.format, to: format) else { return nil }
        let frameCapacity = AVAudioFrameCount(
            Double(buffer.frameLength) * format.sampleRate / buffer.format.sampleRate
        )
        guard let outputBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCapacity) else { return nil }

        var error: NSError?
        var consumed = false
        converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return buffer
        }
        return error == nil ? outputBuffer : nil
    }

    private func waitForPlaybackCompletion() async {
        guard let playerNode else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            playerNode.scheduleBuffer(
                AVAudioPCMBuffer(
                    pcmFormat: playerNode.outputFormat(forBus: 0),
                    frameCapacity: 0
                )!
            ) {
                continuation.resume()
            }
        }
    }

    // MARK: - Sentence Splitting

    private func splitIntoSentences(_ text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var sentences: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            sentences.append(String(text[range]))
            return true
        }
        return sentences.isEmpty ? [text] : sentences
    }

    // MARK: - Idle Timer

    private func startIdleTimer() {
        idleTimer?.invalidate()
        idleTimer = Timer.scheduledTimer(withTimeInterval: Self.idleTimeout, repeats: false) { [weak self] _ in
            Task { @MainActor in
                self?.unloadModel()
            }
        }
    }

    private func resetIdleTimer() {
        idleTimer?.invalidate()
        idleTimer = nil
    }

    // MARK: - State

    private func setPlaybackState(_ state: PlaybackState) {
        playbackState = state
        onStateChange?(state)
    }
}

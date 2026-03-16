import AVFoundation
import NaturalLanguage
import MLXAudioTTS
import MLXLMCommon

@MainActor
final class MLXTTSEngine: NSObject, VoiceEngine {

    private(set) var playbackState: PlaybackState = .idle
    var onStateChange: ((PlaybackState) -> Void)?
    var onError: ((String) -> Void)?
    var selectedVoiceId: String?
    var rate: Float = 1.0

    let modelConfig: MurmurModel
    private var model: (any SpeechGenerationModel)?
    private var generationTask: Task<Void, Never>?
    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var timePitchNode: AVAudioUnitTimePitch?
    private var connectedFormat: AVAudioFormat?
    private var idleTimer: Timer?

    private static let idleTimeout: TimeInterval = 300 // 5 minutes

    init(model: MurmurModel) {
        self.modelConfig = model
        super.init()
    }

    deinit {
        MainActor.assumeIsolated {
            idleTimer?.invalidate()
        }
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
                let chunks = self.chunkSentences(sentences)
                self.prepareAudioNodes()

                try await self.synthesizeAllAndPlay(chunks)

                if !Task.isCancelled {
                    await self.waitForPlaybackCompletion()
                    self.setPlaybackState(.idle)
                }
            } catch {
                if !Task.isCancelled {
                    print("[MLXTTSEngine] Synthesis error: \(error)")
                    self.onError?(error.localizedDescription)
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
        connectedFormat = nil
        if playbackState != .idle {
            setPlaybackState(.idle)
        }
    }

    private(set) lazy var availableVoices: [VoiceInfo] = modelConfig.defaultVoices

    // MARK: - Model Management

    private func ensureModelLoaded() async throws {
        if model == nil {
            print("[MLXTTSEngine] Loading model: \(modelConfig.modelRepo) (type: \(modelConfig.modelType))")
            model = try await TTS.loadModel(
                modelRepo: modelConfig.modelRepo,
                modelType: modelConfig.modelType
            )
            print("[MLXTTSEngine] Model loaded successfully")
        }
    }

    func unloadModel() {
        model = nil
    }

    // MARK: - Audio Chain

    private func prepareAudioNodes() {
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        let timePitch = AVAudioUnitTimePitch()

        timePitch.rate = rate

        engine.attach(player)
        engine.attach(timePitch)

        self.audioEngine = engine
        self.playerNode = player
        self.timePitchNode = timePitch
    }

    private func connectAndStart(format: AVAudioFormat) throws {
        guard let engine = audioEngine, let player = playerNode, let timePitch = timePitchNode else { return }
        engine.connect(player, to: timePitch, format: format)
        engine.connect(timePitch, to: engine.mainMixerNode, format: format)
        try engine.start()
        player.play()
        self.connectedFormat = format
    }

    // MARK: - Chunking

    private func chunkSentences(_ sentences: [String]) -> [String] {
        let maxChars = modelConfig.maxChunkCharacters
        var chunks: [String] = []
        var current = ""

        for sentence in sentences {
            let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }

            if current.isEmpty {
                current = trimmed
            } else if current.count + trimmed.count + 1 <= maxChars {
                current += " " + trimmed
            } else {
                chunks.append(current)
                current = trimmed
            }
        }
        if !current.isEmpty {
            chunks.append(current)
        }
        return chunks
    }

    // MARK: - Synthesis

    private func synthesizeAllAndPlay(_ chunks: [String]) async throws {
        guard let model, let playerNode else { return }

        let voice = selectedVoiceId ?? modelConfig.defaultVoices.first?.id ?? "default"

        for chunk in chunks {
            if Task.isCancelled { break }

            print("[MLXTTSEngine] Synthesizing chunk (\(chunk.count) chars) with model=\(modelConfig.displayName) voice=\(voice)")

            let stream = model.generatePCMBufferStream(
                text: chunk,
                voice: voice,
                refAudio: nil,
                refText: nil,
                language: nil
            )

            for try await buffer in stream {
                if Task.isCancelled { break }

                if connectedFormat == nil {
                    try connectAndStart(format: buffer.format)
                }

                await playerNode.scheduleBuffer(buffer)
            }
        }
    }

    private func waitForPlaybackCompletion() async {
        guard let playerNode, let connectedFormat else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            playerNode.scheduleBuffer(
                AVAudioPCMBuffer(
                    pcmFormat: connectedFormat,
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

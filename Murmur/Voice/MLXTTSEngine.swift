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
    private var generationId: Int = 0
    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var timePitchNode: AVAudioUnitTimePitch?
    private var connectedFormat: AVAudioFormat?
    private var idleTimer: Timer?

    private static let idleTimeout: TimeInterval = 300 // 5 minutes
    private static let defaultGenerationParams = GenerateParameters(
        temperature: 0.75,
        repetitionPenalty: 1.1,
        repetitionContextSize: 64
    )

    init(model: MurmurModel) {
        self.modelConfig = model
        super.init()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAudioConfigChange),
            name: .AVAudioEngineConfigurationChange,
            object: nil
        )
    }

    deinit {
        MainActor.assumeIsolated {
            idleTimer?.invalidate()
            NotificationCenter.default.removeObserver(self)
        }
    }

    // MARK: - VoiceEngine

    func speak(_ text: String) {
        stop()
        setPlaybackState(.speaking)
        resetIdleTimer()

        generationId += 1
        let currentId = generationId

        generationTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.ensureModelLoaded()
                guard self.generationId == currentId else { return }

                let normalizedText = self.normalizeText(text)
                let sentences = self.splitIntoSentences(normalizedText)
                let chunks = self.chunkSentences(sentences)

                try await self.synthesizeAllAndPlay(chunks, generationId: currentId)

                if !Task.isCancelled, self.generationId == currentId {
                    await self.waitForPlaybackCompletion()
                    self.setPlaybackState(.idle)
                }
            } catch {
                if !Task.isCancelled, self.generationId == currentId {
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
        // Keep audio nodes alive — just reset connection state so next speak reconnects
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
        teardownAudio()
    }

    // MARK: - Audio Chain

    private func ensureAudioReady(format: AVAudioFormat) throws {
        // Create nodes if needed
        if audioEngine == nil {
            let engine = AVAudioEngine()
            let player = AVAudioPlayerNode()
            let timePitch = AVAudioUnitTimePitch()

            engine.attach(player)
            engine.attach(timePitch)

            self.audioEngine = engine
            self.playerNode = player
            self.timePitchNode = timePitch
        }

        guard let engine = audioEngine, let player = playerNode, let timePitch = timePitchNode else { return }

        // Always update rate
        timePitch.rate = rate

        // Reconnect if format changed or not yet connected
        if connectedFormat != format {
            if connectedFormat != nil {
                engine.disconnectNodeOutput(player)
                engine.disconnectNodeOutput(timePitch)
            }
            engine.connect(player, to: timePitch, format: format)
            engine.connect(timePitch, to: engine.mainMixerNode, format: format)
            connectedFormat = format
        }

        if !engine.isRunning {
            try engine.start()
        }
        if !player.isPlaying {
            player.play()
        }
    }

    private func teardownAudio() {
        playerNode?.stop()
        audioEngine?.stop()
        audioEngine = nil
        playerNode = nil
        timePitchNode = nil
        connectedFormat = nil
    }

    @objc nonisolated private func handleAudioConfigChange(_ notification: Notification) {
        Task { @MainActor in
            // Reset connection state so next buffer triggers reconnect
            connectedFormat = nil
        }
    }

    private func normalizeText(_ text: String) -> String {
        text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
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

    private func synthesizeAllAndPlay(_ chunks: [String], generationId: Int) async throws {
        guard let model else { return }

        let voice = selectedVoiceId ?? modelConfig.defaultVoices.first?.id ?? "default"
        let params = Self.defaultGenerationParams

        for (i, chunk) in chunks.enumerated() {
            if Task.isCancelled || self.generationId != generationId { break }

            print("[MLXTTSEngine] Synthesizing chunk \(i + 1)/\(chunks.count) (\(chunk.count) chars)")

            let stream = model.generatePCMBufferStream(
                text: chunk,
                voice: voice,
                refAudio: nil,
                refText: nil,
                language: nil,
                generationParameters: params
            )

            // Collect all buffers for this chunk before scheduling any
            var chunkBuffers: [AVAudioPCMBuffer] = []
            for try await buffer in stream {
                if Task.isCancelled || self.generationId != generationId { break }
                chunkBuffers.append(buffer)
            }

            if Task.isCancelled || self.generationId != generationId { break }

            // Ensure audio chain is ready (using first buffer's format)
            if let first = chunkBuffers.first, connectedFormat == nil {
                try ensureAudioReady(format: first.format)
            }

            // Schedule entire chunk at once — smooth playback guaranteed
            for buffer in chunkBuffers {
                playerNode?.scheduleBuffer(buffer, completionHandler: nil)
            }
        }
    }

    /// Waits for all queued buffers to finish playing by scheduling a zero-frame
    /// sentinel buffer whose completion handler signals the continuation.
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

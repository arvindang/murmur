import AVFoundation
import NaturalLanguage

@MainActor
final class OpenAITTSEngine: VoiceEngine {

    private(set) var playbackState: PlaybackState = .idle
    var onStateChange: ((PlaybackState) -> Void)?
    var onError: ((String) -> Void)?
    var selectedVoiceId: String?
    var rate: Float = 1.0

    private var streamTask: Task<Void, Never>?
    private var generationId: Int = 0
    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?

    private static let apiURL = URL(string: "https://api.openai.com/v1/audio/speech")!
    private static let sampleRate: Double = 24_000
    private static let maxChunkChars = 4096
    // 100ms at 24kHz = 2400 frames = 4800 bytes (16-bit mono)
    private static let bufferFrames: AVAudioFrameCount = 2400
    private static let bufferByteCount = 4800

    private static let outputFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: sampleRate,
        channels: 1,
        interleaved: false
    )!

    // MARK: - Available Voices

    static let voices: [VoiceInfo] = [
        VoiceInfo(id: "alloy", name: "Alloy", language: "Multilingual", quality: .premium, group: "OpenAI"),
        VoiceInfo(id: "ash", name: "Ash", language: "Multilingual", quality: .premium, group: "OpenAI"),
        VoiceInfo(id: "ballad", name: "Ballad", language: "Multilingual", quality: .premium, group: "OpenAI"),
        VoiceInfo(id: "coral", name: "Coral", language: "Multilingual", quality: .premium, group: "OpenAI"),
        VoiceInfo(id: "echo", name: "Echo", language: "Multilingual", quality: .premium, group: "OpenAI"),
        VoiceInfo(id: "fable", name: "Fable", language: "Multilingual", quality: .premium, group: "OpenAI"),
        VoiceInfo(id: "nova", name: "Nova", language: "Multilingual", quality: .premium, group: "OpenAI"),
        VoiceInfo(id: "onyx", name: "Onyx", language: "Multilingual", quality: .premium, group: "OpenAI"),
        VoiceInfo(id: "sage", name: "Sage", language: "Multilingual", quality: .premium, group: "OpenAI"),
        VoiceInfo(id: "shimmer", name: "Shimmer", language: "Multilingual", quality: .premium, group: "OpenAI"),
        VoiceInfo(id: "verse", name: "Verse", language: "Multilingual", quality: .premium, group: "OpenAI"),
    ]

    var availableVoices: [VoiceInfo] { Self.voices }

    // MARK: - VoiceEngine

    func speak(_ text: String) {
        stop()
        setPlaybackState(.speaking)

        generationId += 1
        let currentId = generationId

        let normalizedText = text
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        let chunks: [String]
        if normalizedText.count <= Self.maxChunkChars {
            chunks = [normalizedText]
        } else {
            chunks = splitIntoChunks(normalizedText)
        }

        streamTask = Task { [weak self] in
            guard let self else { return }
            do {
                for chunk in chunks {
                    if Task.isCancelled || self.generationId != currentId { break }
                    try await self.streamChunk(chunk)
                }
                if !Task.isCancelled, self.generationId == currentId {
                    await self.waitForPlaybackCompletion()
                    self.setPlaybackState(.idle)
                }
            } catch {
                if !Task.isCancelled, self.generationId == currentId {
                    self.onError?(error.localizedDescription)
                    self.setPlaybackState(.idle)
                }
            }
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
        streamTask?.cancel()
        streamTask = nil
        playerNode?.stop()
        if playbackState != .idle {
            setPlaybackState(.idle)
        }
    }

    // MARK: - Streaming

    private func streamChunk(_ text: String) async throws {
        guard let apiKey = KeychainHelper.loadAPIKey() else {
            onError?("No OpenAI API key — add one in Settings")
            setPlaybackState(.idle)
            return
        }

        let voice = selectedVoiceId ?? "nova"

        var request = URLRequest(url: Self.apiURL)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "model": "gpt-4o-mini-tts",
            "input": text,
            "voice": voice,
            "response_format": "pcm",
            "speed": Double(rate),
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (asyncBytes, response) = try await URLSession.shared.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OpenAITTSError.invalidResponse
        }

        if httpResponse.statusCode != 200 {
            // Collect error body
            var errorData = Data()
            for try await byte in asyncBytes {
                errorData.append(byte)
                if errorData.count > 4096 { break }
            }
            let message = Self.parseErrorMessage(data: errorData, statusCode: httpResponse.statusCode)
            throw OpenAITTSError.apiError(message)
        }

        try ensureAudioReady()

        var accumulated = Data()
        accumulated.reserveCapacity(Self.bufferByteCount * 4)

        for try await byte in asyncBytes {
            if Task.isCancelled { break }
            accumulated.append(byte)

            while accumulated.count >= Self.bufferByteCount {
                let chunk = accumulated.prefix(Self.bufferByteCount)
                accumulated.removeFirst(Self.bufferByteCount)
                let buffer = Self.pcmDataToBuffer(chunk)
                playerNode?.scheduleBuffer(buffer, completionHandler: nil)
            }
        }

        // Flush remaining bytes
        if !accumulated.isEmpty, !Task.isCancelled {
            let frameCount = AVAudioFrameCount(accumulated.count / 2)
            if frameCount > 0 {
                let buffer = Self.pcmDataToBuffer(accumulated.prefix(Int(frameCount) * 2))
                playerNode?.scheduleBuffer(buffer, completionHandler: nil)
            }
        }
    }

    // MARK: - Audio Chain

    private func ensureAudioReady() throws {
        if audioEngine == nil {
            let engine = AVAudioEngine()
            let player = AVAudioPlayerNode()

            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: Self.outputFormat)

            self.audioEngine = engine
            self.playerNode = player
        }

        guard let engine = audioEngine, let player = playerNode else { return }

        if !engine.isRunning {
            try engine.start()
        }
        if !player.isPlaying {
            player.play()
        }
    }

    /// Convert raw 16-bit signed LE PCM data to a float32 AVAudioPCMBuffer.
    private static func pcmDataToBuffer(_ data: Data) -> AVAudioPCMBuffer {
        let frameCount = AVAudioFrameCount(data.count / 2)
        let buffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: frameCount)!
        buffer.frameLength = frameCount

        let floatPtr = buffer.floatChannelData![0]
        data.withUnsafeBytes { rawPtr in
            let int16Ptr = rawPtr.bindMemory(to: Int16.self)
            for i in 0..<Int(frameCount) {
                floatPtr[i] = Float(int16Ptr[i]) / 32768.0
            }
        }
        return buffer
    }

    private func waitForPlaybackCompletion() async {
        guard let playerNode else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            playerNode.scheduleBuffer(
                AVAudioPCMBuffer(pcmFormat: Self.outputFormat, frameCapacity: 0)!
            ) {
                continuation.resume()
            }
        }
    }

    // MARK: - Text Chunking

    private func splitIntoChunks(_ text: String) -> [String] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        var sentences: [String] = []
        tokenizer.enumerateTokens(in: text.startIndex..<text.endIndex) { range, _ in
            sentences.append(String(text[range]))
            return true
        }
        if sentences.isEmpty { sentences = [text] }

        var chunks: [String] = []
        var current = ""
        for sentence in sentences {
            let trimmed = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            if current.isEmpty {
                current = trimmed
            } else if current.count + trimmed.count + 1 <= Self.maxChunkChars {
                current += " " + trimmed
            } else {
                chunks.append(current)
                current = trimmed
            }
        }
        if !current.isEmpty { chunks.append(current) }
        return chunks
    }

    // MARK: - Error Handling

    private static func parseErrorMessage(data: Data, statusCode: Int) -> String {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = json["error"] as? [String: Any],
           let message = error["message"] as? String {
            return message
        }
        switch statusCode {
        case 401: return "Invalid API key"
        case 429: return "Rate limited — try again in a moment"
        default: return "API error (HTTP \(statusCode))"
        }
    }

    // MARK: - State

    private func setPlaybackState(_ state: PlaybackState) {
        playbackState = state
        onStateChange?(state)
    }
}

// MARK: - Error Type

private enum OpenAITTSError: LocalizedError {
    case invalidResponse
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "Invalid response from OpenAI"
        case .apiError(let message): message
        }
    }
}

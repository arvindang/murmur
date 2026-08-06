import AVFoundation
import Foundation

@MainActor
final class OpenAITTSEngine: VoiceEngine {

    private(set) var playbackState: PlaybackState = .idle
    var onStateChange: ((PlaybackState) -> Void)?
    var onError: ((String) -> Void)?
    var selectedVoiceId: String?
    var rate: Float = 1.0

    private var streamTask: Task<Void, Never>?
    private var watchdogTask: Task<Void, Never>?
    private var generationId: UInt64 = 0
    private var audioEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var scheduledBufferCount = 0
    private var finishedScheduling = false
    private var didScheduleAudio = false
    private var lastPlaybackProgress = Date()
    private let urlSession: URLSession

    private static let apiURL = URL(string: "https://api.openai.com/v1/audio/speech")!
    private static let sampleRate: Double = 24_000
    private static let maxChunkCharacters = 2_000
    private static let maxRequestAttempts = 3

    // Queue 250ms buffers and apply backpressure after 30 seconds of generated audio.
    // This keeps a fast startup without allowing a long article to consume unbounded memory.
    private static let bufferByteCount = 12_000
    private static let maxScheduledBuffers = 120
    private static let playbackStallTimeout: TimeInterval = 15

    private static let outputFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: sampleRate,
        channels: 1,
        interleaved: false
    )!

    init(urlSession: URLSession? = nil) {
        if let urlSession {
            self.urlSession = urlSession
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = 20
            configuration.timeoutIntervalForResource = 10 * 60
            configuration.waitsForConnectivity = false
            self.urlSession = URLSession(configuration: configuration)
        }
    }

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
        VoiceInfo(id: "marin", name: "Marin", language: "Multilingual", quality: .premium, group: "OpenAI"),
        VoiceInfo(id: "cedar", name: "Cedar", language: "Multilingual", quality: .premium, group: "OpenAI"),
    ]

    var availableVoices: [VoiceInfo] { Self.voices }

    // MARK: - VoiceEngine

    func speak(_ text: String) {
        let chunks = SpeechTextChunker.chunks(
            for: text,
            maxCharacters: Self.maxChunkCharacters
        )
        guard !chunks.isEmpty else { return }

        stop()
        generationId &+= 1
        let currentId = generationId

        scheduledBufferCount = 0
        finishedScheduling = false
        didScheduleAudio = false
        lastPlaybackProgress = Date()
        setPlaybackState(.speaking)
        startWatchdog(generationId: currentId)

        streamTask = Task { [weak self] in
            guard let self else { return }

            do {
                for chunk in chunks {
                    try Task.checkCancellation()
                    guard self.generationId == currentId else { throw CancellationError() }
                    try await self.streamChunk(chunk, generationId: currentId)
                }

                try Task.checkCancellation()
                guard self.generationId == currentId else { return }
                guard self.didScheduleAudio else { throw OpenAITTSError.emptyAudio }

                self.streamTask = nil
                self.finishedScheduling = true
                self.finishPlaybackIfReady(generationId: currentId)
            } catch is CancellationError {
                // stop() owns state cleanup for intentional cancellation.
            } catch {
                self.handleFailure(error.localizedDescription, generationId: currentId)
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
        do {
            try ensureAudioReady()
            playerNode?.play()
            lastPlaybackProgress = Date()
            setPlaybackState(.speaking)
        } catch {
            handleFailure(error.localizedDescription, generationId: generationId)
        }
    }

    func stop() {
        generationId &+= 1
        streamTask?.cancel()
        watchdogTask?.cancel()
        streamTask = nil
        watchdogTask = nil
        playerNode?.stop()
        scheduledBufferCount = 0
        finishedScheduling = false
        didScheduleAudio = false

        if playbackState != .idle {
            setPlaybackState(.idle)
        }
    }

    // MARK: - Streaming

    private func streamChunk(_ text: String, generationId currentId: UInt64) async throws {
        guard let apiKey = KeychainHelper.loadAPIKey() else {
            throw OpenAITTSError.missingAPIKey
        }

        var request = URLRequest(url: Self.apiURL, timeoutInterval: 20)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("audio/pcm", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": "gpt-4o-mini-tts",
            "input": text,
            "voice": selectedVoiceId ?? "nova",
            "response_format": "pcm",
            "speed": Double(rate.clamped(to: 0.25...4.0)),
        ])

        for attempt in 0..<Self.maxRequestAttempts {
            try Task.checkCancellation()
            guard generationId == currentId else { throw CancellationError() }

            var scheduledAudioThisAttempt = false

            do {
                let (asyncBytes, response) = try await urlSession.bytes(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw OpenAITTSError.invalidResponse
                }

                guard httpResponse.statusCode == 200 else {
                    let errorData = try await Self.readErrorBody(from: asyncBytes)
                    let message = Self.parseErrorMessage(
                        data: errorData,
                        statusCode: httpResponse.statusCode
                    )

                    if Self.isRetryableStatus(httpResponse.statusCode),
                       attempt + 1 < Self.maxRequestAttempts {
                        try await Self.waitBeforeRetry(attempt: attempt, response: httpResponse)
                        continue
                    }

                    throw OpenAITTSError.apiError(message)
                }

                try ensureAudioReady()

                var accumulated = Data()
                accumulated.reserveCapacity(Self.bufferByteCount * 2)

                for try await byte in asyncBytes {
                    accumulated.append(byte)

                    while accumulated.count >= Self.bufferByteCount {
                        try Task.checkCancellation()
                        guard generationId == currentId else { throw CancellationError() }

                        let pcmData = Data(accumulated.prefix(Self.bufferByteCount))
                        accumulated.removeFirst(Self.bufferByteCount)
                        try await schedulePCMData(pcmData, generationId: currentId)
                        scheduledAudioThisAttempt = true
                    }
                }

                if !accumulated.isEmpty {
                    let completeByteCount = accumulated.count - (accumulated.count % 2)
                    if completeByteCount > 0 {
                        try await schedulePCMData(
                            Data(accumulated.prefix(completeByteCount)),
                            generationId: currentId
                        )
                        scheduledAudioThisAttempt = true
                    }
                }

                guard scheduledAudioThisAttempt else { throw OpenAITTSError.emptyAudio }
                return
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // Retrying after audio was queued would repeat speech the user already heard.
                guard !scheduledAudioThisAttempt,
                      attempt + 1 < Self.maxRequestAttempts,
                      Self.isRetryableNetworkError(error)
                else {
                    throw error
                }

                try await Self.waitBeforeRetry(attempt: attempt, response: nil)
            }
        }
    }

    private func schedulePCMData(_ data: Data, generationId currentId: UInt64) async throws {
        while scheduledBufferCount >= Self.maxScheduledBuffers {
            try Task.checkCancellation()
            guard generationId == currentId else { throw CancellationError() }
            try await Task.sleep(for: .milliseconds(50))
        }

        guard generationId == currentId else { throw CancellationError() }
        let buffer = Self.pcmDataToBuffer(data)
        if scheduledBufferCount == 0 {
            lastPlaybackProgress = Date()
        }
        scheduledBufferCount += 1
        didScheduleAudio = true

        let completion: @Sendable () -> Void = { [weak self] in
            Task { @MainActor in
                self?.audioBufferDidFinish(generationId: currentId)
            }
        }

        if let playerNode {
            MurmurScheduleBufferUntilPlayedBack(playerNode, buffer, completion)
        }
    }

    // MARK: - Audio Chain

    private func ensureAudioReady() throws {
        if audioEngine == nil {
            let engine = AVAudioEngine()
            let player = AVAudioPlayerNode()

            engine.attach(player)
            engine.connect(player, to: engine.mainMixerNode, format: Self.outputFormat)

            audioEngine = engine
            playerNode = player
        }

        guard let engine = audioEngine, let player = playerNode else {
            throw OpenAITTSError.audioUnavailable
        }

        if !engine.isRunning {
            try engine.start()
        }
        if !player.isPlaying, playbackState != .paused {
            player.play()
        }
    }

    /// Convert raw 16-bit signed little-endian PCM data to a float32 audio buffer.
    private static func pcmDataToBuffer(_ data: Data) -> AVAudioPCMBuffer {
        let frameCount = AVAudioFrameCount(data.count / 2)
        let buffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: frameCount)!
        buffer.frameLength = frameCount

        let floatPointer = buffer.floatChannelData![0]
        data.withUnsafeBytes { rawBytes in
            for frame in 0..<Int(frameCount) {
                let sample = rawBytes.loadUnaligned(
                    fromByteOffset: frame * MemoryLayout<Int16>.size,
                    as: Int16.self
                )
                floatPointer[frame] = Float(Int16(littleEndian: sample)) / 32768.0
            }
        }
        return buffer
    }

    private func audioBufferDidFinish(generationId currentId: UInt64) {
        guard generationId == currentId else { return }
        scheduledBufferCount = max(0, scheduledBufferCount - 1)
        lastPlaybackProgress = Date()
        finishPlaybackIfReady(generationId: currentId)
    }

    private func finishPlaybackIfReady(generationId currentId: UInt64) {
        guard generationId == currentId,
              finishedScheduling,
              scheduledBufferCount == 0
        else {
            return
        }

        watchdogTask?.cancel()
        watchdogTask = nil
        streamTask = nil
        finishedScheduling = false
        setPlaybackState(.idle)
    }

    // MARK: - Watchdog

    private func startWatchdog(generationId currentId: UInt64) {
        watchdogTask?.cancel()
        watchdogTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(2))
                } catch {
                    return
                }

                guard let self,
                      self.generationId == currentId,
                      self.playbackState != .idle
                else {
                    return
                }

                if self.playbackState == .paused {
                    self.lastPlaybackProgress = Date()
                    continue
                }

                guard self.scheduledBufferCount > 0,
                      Date().timeIntervalSince(self.lastPlaybackProgress) > Self.playbackStallTimeout
                else {
                    continue
                }

                if self.audioEngine?.isRunning != true || self.playerNode?.isPlaying != true {
                    do {
                        try self.ensureAudioReady()
                        self.playerNode?.play()
                        self.lastPlaybackProgress = Date()
                    } catch {
                        self.handleFailure(error.localizedDescription, generationId: currentId)
                        return
                    }
                } else {
                    self.handleFailure("Audio playback stalled", generationId: currentId)
                    return
                }
            }
        }
    }

    // MARK: - Retry and Error Handling

    private static func readErrorBody(from bytes: URLSession.AsyncBytes) async throws -> Data {
        var data = Data()
        for try await byte in bytes {
            data.append(byte)
            if data.count >= 4_096 { break }
        }
        return data
    }

    private static func waitBeforeRetry(
        attempt: Int,
        response: HTTPURLResponse?
    ) async throws {
        let retryAfter = response?
            .value(forHTTPHeaderField: "Retry-After")
            .flatMap(Double.init)
        let seconds = min(max(retryAfter ?? (0.75 * pow(2, Double(attempt))), 0.25), 5)
        try await Task.sleep(for: .milliseconds(Int(seconds * 1_000)))
    }

    private static func isRetryableStatus(_ statusCode: Int) -> Bool {
        statusCode == 408 || statusCode == 429 || (500...599).contains(statusCode)
    }

    private static func isRetryableNetworkError(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        return [
            .timedOut,
            .cannotFindHost,
            .cannotConnectToHost,
            .dnsLookupFailed,
            .networkConnectionLost,
            .notConnectedToInternet,
            .resourceUnavailable,
        ].contains(urlError.code)
    }

    private static func parseErrorMessage(data: Data, statusCode: Int) -> String {
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let error = json["error"] as? [String: Any],
           let message = error["message"] as? String {
            return message
        }
        switch statusCode {
        case 401: return "Invalid API key"
        case 408: return "The speech request timed out"
        case 429: return "Rate limited — try again in a moment"
        case 500...599: return "OpenAI is temporarily unavailable (HTTP \(statusCode))"
        default: return "API error (HTTP \(statusCode))"
        }
    }

    private func handleFailure(_ message: String, generationId currentId: UInt64) {
        guard generationId == currentId else { return }

        generationId &+= 1
        streamTask?.cancel()
        watchdogTask?.cancel()
        streamTask = nil
        watchdogTask = nil
        playerNode?.stop()
        scheduledBufferCount = 0
        finishedScheduling = false
        didScheduleAudio = false
        onError?(message)
        setPlaybackState(.idle)
    }

    private func setPlaybackState(_ state: PlaybackState) {
        playbackState = state
        onStateChange?(state)
    }
}

private enum OpenAITTSError: LocalizedError {
    case invalidResponse
    case emptyAudio
    case missingAPIKey
    case audioUnavailable
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: "Invalid response from OpenAI"
        case .emptyAudio: "OpenAI returned no audio"
        case .missingAPIKey: "No OpenAI API key — add one in Settings"
        case .audioUnavailable: "Audio output is unavailable"
        case .apiError(let message): message
        }
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

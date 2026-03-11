import Foundation
import MLXAudioTTS

enum ModelState: Sendable, Equatable {
    case notDownloaded
    case downloading
    case downloaded
    case error(String)
}

@MainActor
@Observable
final class ModelManager {

    private(set) var sopranoModelState: ModelState = .notDownloaded

    private static let modelId = "mlx-community/Soprano-80M-bf16"

    func checkModelAvailability() {
        let cacheDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/huggingface/hub/models--mlx-community--Soprano-80M-bf16")
        if FileManager.default.fileExists(atPath: cacheDir.path) {
            sopranoModelState = .downloaded
        } else {
            sopranoModelState = .notDownloaded
        }
    }

    func downloadModel() async {
        guard sopranoModelState != .downloading else { return }
        sopranoModelState = .downloading
        do {
            let _ = try await SopranoModel.fromPretrained(Self.modelId)
            sopranoModelState = .downloaded
        } catch {
            sopranoModelState = .error(error.localizedDescription)
        }
    }
}

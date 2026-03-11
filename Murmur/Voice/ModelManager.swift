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

    private(set) var modelStates: [MurmurModel: ModelState] = [:]

    init() {
        for model in MurmurModel.allCases {
            checkModelAvailability(for: model)
        }
    }

    func state(for model: MurmurModel) -> ModelState {
        modelStates[model] ?? .notDownloaded
    }

    func checkModelAvailability(for model: MurmurModel) {
        let cacheDir = cacheDirectory(for: model)
        if FileManager.default.fileExists(atPath: cacheDir.path) {
            modelStates[model] = .downloaded
        } else {
            modelStates[model] = .notDownloaded
        }
    }

    func downloadModel(_ model: MurmurModel) async {
        guard state(for: model) != .downloading else { return }
        modelStates[model] = .downloading
        do {
            let _ = try await TTS.loadModel(
                modelRepo: model.modelRepo,
                modelType: model.modelType
            )
            modelStates[model] = .downloaded
        } catch {
            modelStates[model] = .error(error.localizedDescription)
        }
    }

    func deleteModel(_ model: MurmurModel) {
        let cacheDir = cacheDirectory(for: model)
        try? FileManager.default.removeItem(at: cacheDir)
        modelStates[model] = .notDownloaded
    }

    private func cacheDirectory(for model: MurmurModel) -> URL {
        let repoSlug = model.modelRepo.replacingOccurrences(of: "/", with: "--")
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cache/huggingface/hub/models--\(repoSlug)")
    }
}

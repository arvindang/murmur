import SwiftUI
import Defaults
import KeyboardShortcuts
import LaunchAtLogin

struct SettingsView: View {
    var body: some View {
        TabView {
            GeneralTab()
                .tabItem {
                    Label("General", systemImage: "gear")
                }

            VoiceTab()
                .tabItem {
                    Label("Voice", systemImage: "waveform")
                }
        }
        .frame(width: 450, height: 400)
        .onAppear {
            AppState.isOpeningSettings = true
            NSApp.setActivationPolicy(.regular)
            NSApp.activate()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                AppState.isOpeningSettings = false
            }
        }
    }
}

// MARK: - General

private struct GeneralTab: View {
    var body: some View {
        Form {
            Section("Hotkey") {
                KeyboardShortcuts.Recorder("Read Aloud:", name: .readAloud)
            }

            Section("Startup") {
                LaunchAtLogin.Toggle("Launch at login")
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Voice

private struct VoiceTab: View {
    @Environment(AppState.self) private var appState
    @Default(.voiceEngineType) private var engineType
    @Default(.murmurModel) private var murmurModel
    @Default(.speakingRate) private var speakingRate

    var body: some View {
        Form {
            Section("Engine") {
                Picker("Voice Engine:", selection: $engineType) {
                    Text("System Voices").tag(VoiceEngineType.system)
                    Text("Murmur Voice").tag(VoiceEngineType.murmur)
                }
                .pickerStyle(.segmented)
                .onChange(of: engineType) { _, newValue in
                    appState.switchEngine(to: newValue)
                }

                if engineType == .murmur {
                    Picker("Model:", selection: $murmurModel) {
                        ForEach(MurmurModel.allCases, id: \.self) { model in
                            Text(model.dropdownLabel).tag(model)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: murmurModel) { _, newValue in
                        appState.switchMurmurModel(to: newValue)
                    }

                    ModelDetailView(model: murmurModel)
                }
            }

            Section("Voice") {
                if engineType == .system {
                    Text("System Default")
                        .foregroundStyle(.secondary)
                } else {
                    MurmurVoicePicker(model: murmurModel)
                }

                Button("Preview Voice") {
                    let voiceId = engineType == .system
                        ? Defaults[.selectedVoiceId]
                        : Defaults[.murmurVoiceId]
                    appState.previewVoice(id: voiceId)
                }
                .disabled(appState.playbackState == .speaking ||
                          (engineType == .murmur && appState.modelManager.state(for: murmurModel) != .downloaded))
            }

            Section("Speed") {
                HStack {
                    Text("\(speakingRate, specifier: "%.2f")x")
                        .monospacedDigit()
                        .frame(width: 50)
                    Slider(value: $speakingRate, in: 0.5...2.0, step: 0.25)
                }
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Murmur Voice Picker

private struct MurmurVoicePicker: View {
    let model: MurmurModel
    @Default(.murmurVoiceId) private var murmurVoiceId

    var body: some View {
        let voices = model.defaultVoices
        if voices.count <= 1 {
            Text(voices.first?.name ?? model.displayName)
                .foregroundStyle(.secondary)
        } else {
            Picker("Voice:", selection: $murmurVoiceId) {
                ForEach(voices) { voice in
                    Text("\(voice.name) (\(voice.language))").tag(voice.id)
                }
            }
        }
    }
}

// MARK: - Model Detail View

private struct ModelDetailView: View {
    @Environment(AppState.self) private var appState
    let model: MurmurModel
    @State private var showDeleteConfirmation = false

    var body: some View {
        LabeledContent("Languages:") {
            Text(model.supportedLanguages.joined(separator: ", "))
                .foregroundStyle(.secondary)
        }

        LabeledContent("Size:") {
            Text(model.approxSize)
                .foregroundStyle(.secondary)
        }

        HStack {
            Text("Status:")

            Spacer()

            switch appState.modelManager.state(for: model) {
            case .notDownloaded:
                Button("Download (\(model.approxSize))") {
                    Task {
                        await appState.modelManager.downloadModel(model)
                    }
                }

            case .downloading:
                ProgressView()
                    .controlSize(.small)
                Text("Downloading...")
                    .foregroundStyle(.secondary)

            case .downloaded:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.murmurAmber)
                Text("Ready")
                    .foregroundStyle(.secondary)
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Delete \(model.displayName) model")

            case .error(let message):
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                Text("Error")
                    .foregroundStyle(.secondary)
                    .help(message)
                Button("Retry") {
                    Task {
                        await appState.modelManager.downloadModel(model)
                    }
                }
            }
        }
        .alert("Delete \(model.displayName) Model?", isPresented: $showDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                appState.deleteModel(model)
            }
        } message: {
            Text("This will remove the model (\(model.approxSize)) and switch to System Voices. You can re-download it later.")
        }
    }
}

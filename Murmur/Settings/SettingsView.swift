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
    @Default(.selectedVoiceId) private var selectedVoiceId
    @Default(.speakingRate) private var speakingRate

    var body: some View {
        Form {
            Section("Engine") {
                Picker("Voice Engine:", selection: $engineType) {
                    Text("System Voices").tag(VoiceEngineType.system)
                    Text("Murmur Voice (Soprano)").tag(VoiceEngineType.soprano)
                }
                .pickerStyle(.segmented)
                .onChange(of: engineType) { _, newValue in
                    appState.switchEngine(to: newValue)
                }

                if engineType == .soprano {
                    SopranoModelRow()
                }
            }

            Section("Voice") {
                if engineType == .system {
                    SystemVoicePicker(selectedVoiceId: $selectedVoiceId)
                } else {
                    Text("Soprano")
                        .foregroundStyle(.secondary)
                }

                Button("Preview Voice") {
                    let voiceId = engineType == .system ? selectedVoiceId : ""
                    appState.previewVoice(id: voiceId)
                }
                .disabled(appState.playbackState == .speaking ||
                          (engineType == .soprano && appState.modelManager.sopranoModelState != .downloaded))
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

// MARK: - Soprano Model Row

private struct SopranoModelRow: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        HStack {
            Text("Soprano Model:")

            Spacer()

            switch appState.modelManager.sopranoModelState {
            case .notDownloaded:
                Button("Download") {
                    Task {
                        await appState.modelManager.downloadModel()
                    }
                }

            case .downloading:
                ProgressView()
                    .controlSize(.small)
                Text("Downloading...")
                    .foregroundStyle(.secondary)

            case .downloaded:
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Ready")
                    .foregroundStyle(.secondary)

            case .error(let message):
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.yellow)
                Text("Error")
                    .foregroundStyle(.secondary)
                    .help(message)
                Button("Retry") {
                    Task {
                        await appState.modelManager.downloadModel()
                    }
                }
            }
        }
    }
}

// MARK: - System Voice Picker

private struct SystemVoicePicker: View {
    @Environment(AppState.self) private var appState
    @Binding var selectedVoiceId: String

    private static let qualityLabels: [VoiceInfo.Quality: String] = [
        .premium: "Premium", .enhanced: "Enhanced", .standard: "Standard",
    ]

    var body: some View {
        Picker("Voice:", selection: $selectedVoiceId) {
            Text("System Default").tag("")

            ForEach(groupedVoices, id: \.label) { group in
                Section(group.label) {
                    ForEach(group.voices) { voice in
                        Text(voice.name).tag(voice.id)
                    }
                }
            }
        }
    }

    private struct VoiceGroup {
        let label: String
        let voices: [VoiceInfo]
    }

    private var groupedVoices: [VoiceGroup] {
        let grouped = Dictionary(grouping: appState.availableVoices, by: \.quality)
        return [VoiceInfo.Quality.premium, .enhanced, .standard].compactMap { quality in
            guard let voices = grouped[quality], !voices.isEmpty else { return nil }
            return VoiceGroup(label: Self.qualityLabels[quality]!, voices: voices)
        }
    }
}

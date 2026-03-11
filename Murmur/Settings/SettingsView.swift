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
        .frame(width: 450, height: 300)
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
    @Default(.selectedVoiceId) private var selectedVoiceId
    @Default(.speakingRate) private var speakingRate

    var body: some View {
        Form {
            Section("Voice") {
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

                Button("Preview Voice") {
                    appState.previewVoice(id: selectedVoiceId)
                }
                .disabled(appState.playbackState == .speaking)
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

    private struct VoiceGroup {
        let label: String
        let voices: [VoiceInfo]
    }

    private static let qualityLabels: [VoiceInfo.Quality: String] = [
        .premium: "Premium", .enhanced: "Enhanced", .standard: "Standard",
    ]

    private var groupedVoices: [VoiceGroup] {
        let grouped = Dictionary(grouping: appState.availableVoices, by: \.quality)
        return [VoiceInfo.Quality.premium, .enhanced, .standard].compactMap { quality in
            guard let voices = grouped[quality], !voices.isEmpty else { return nil }
            return VoiceGroup(label: Self.qualityLabels[quality]!, voices: voices)
        }
    }
}

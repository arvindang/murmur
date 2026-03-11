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

    private var groupedVoices: [VoiceGroup] {
        let voices = appState.availableVoices
        var groups: [VoiceGroup] = []

        let premium = voices.filter { $0.quality == .premium }
        if !premium.isEmpty { groups.append(VoiceGroup(label: "Premium", voices: premium)) }

        let enhanced = voices.filter { $0.quality == .enhanced }
        if !enhanced.isEmpty { groups.append(VoiceGroup(label: "Enhanced", voices: enhanced)) }

        let standard = voices.filter { $0.quality == .standard }
        if !standard.isEmpty { groups.append(VoiceGroup(label: "Standard", voices: standard)) }

        return groups
    }
}

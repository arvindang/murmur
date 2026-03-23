import SwiftUI
import Defaults
import KeyboardShortcuts
import LaunchAtLogin

// MARK: - Inline Settings View

struct InlineSettingsView: View {
    @Environment(AppState.self) private var appState
    @Default(.voiceEngineType) private var engineType
    @Default(.speakingRate) private var speakingRate
    @Default(.textSource) private var textSource

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // General
            generalSection
            MurmurDivider()
            // Text Source
            textSourceSection
            MurmurDivider()
            // Voice
            voiceSection
        }
        .padding(.top, 8)
    }

    // MARK: - General

    private var generalSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            MurmurSectionHeader("General")

            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Hotkey:")
                        .frame(width: 70, alignment: .leading)
                    KeyboardShortcuts.Recorder("", name: .readAloud)
                }

                LaunchAtLogin.Toggle("Launch at login")
            }
        }
    }

    // MARK: - Text Source

    @ViewBuilder
    private var textSourceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            MurmurSectionHeader("Text Source")

            Picker("Source:", selection: $textSource) {
                ForEach(TextSource.allCases, id: \.self) { source in
                    Text(source.displayName).tag(source)
                }
            }
            .pickerStyle(.segmented)

            switch textSource {
            case .auto:
                Text("Reads from the focused app, falls back to clipboard")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .accessibility:
                Text("Reads directly from the focused app")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            case .clipboard:
                Text("Only reads from the clipboard")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if textSource != .clipboard {
                AccessibilityWarningRow()
                BrowserAutomationNote()
            }
        }
    }

    // MARK: - Voice

    private var voiceSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            MurmurSectionHeader("Voice")

            VStack(alignment: .leading, spacing: 10) {
                // Engine picker
                Picker("Engine:", selection: $engineType) {
                    Text("System").tag(VoiceEngineType.system)
                    Text("OpenAI").tag(VoiceEngineType.openai)
                }
                .pickerStyle(.segmented)
                .onChange(of: engineType) { _, newValue in
                    appState.switchEngine(to: newValue)
                }

                if engineType == .openai {
                    OpenAISettingsSection()
                }

                MurmurDivider()

                // Voice selection
                if engineType == .system {
                    Text("System Default")
                        .foregroundStyle(.secondary)
                }
                // OpenAI voice picker is inside OpenAISettingsSection

                // Preview
                Button("Preview Voice") {
                    let voiceId: String
                    switch engineType {
                    case .system: voiceId = Defaults[.selectedVoiceId]
                    case .openai: voiceId = Defaults[.openaiVoiceId]
                    }
                    appState.previewVoice(id: voiceId)
                }
                .disabled(appState.playbackState == .speaking ||
                          (engineType == .openai && !KeychainHelper.hasAPIKey()))

                MurmurDivider()

                // Speed
                HStack {
                    Text("Speed:")
                    Text("\(speakingRate, specifier: "%.2f")x")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 45)
                    Slider(value: $speakingRate, in: 0.5...2.0, step: 0.25)
                }
            }
        }
    }
}

// MARK: - OpenAI Settings Section

struct OpenAISettingsSection: View {
    @Default(.openaiVoiceId) private var openaiVoiceId
    @State private var apiKeyInput = ""
    @State private var hasKey = KeychainHelper.hasAPIKey()

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // API key
            if hasKey {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Color.murmurAmber)
                    Text("API key saved")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Remove") {
                        KeychainHelper.deleteAPIKey()
                        hasKey = false
                    }
                    .controlSize(.small)
                }
            } else {
                HStack {
                    SecureField("OpenAI API key", text: $apiKeyInput)
                        .textFieldStyle(.roundedBorder)
                    Button("Save") {
                        let trimmed = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        KeychainHelper.save(apiKey: trimmed)
                        apiKeyInput = ""
                        hasKey = true
                    }
                    .disabled(apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }

            Text("Stored in your Mac's Keychain")
                .font(.caption)
                .foregroundStyle(.secondary)

            // Voice picker
            Picker("Voice:", selection: $openaiVoiceId) {
                ForEach(OpenAITTSEngine.voices) { voice in
                    Text(voice.name).tag(voice.id)
                }
            }
        }
    }
}

// MARK: - Browser Automation Note

private struct BrowserAutomationNote: View {
    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
            Text("Murmur reads web articles by fetching page content directly. Grant Automation access when prompted for best results.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Accessibility Warning Row

private struct AccessibilityWarningRow: View {
    @State private var hasPermission = AccessibilityExtractor.hasPermission
    @State private var grantTapped = false

    var body: some View {
        if !hasPermission {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text("Accessibility access required")
                    .font(.caption)
                Spacer()
                Button("Grant") {
                    grantTapped = true
                    AccessibilityExtractor.openAccessibilitySettings()
                }
                .controlSize(.small)
            }
            .monitorAccessibilityPermission($hasPermission, grantTapped: grantTapped)
        }
    }
}

import SwiftUI
import Defaults
import KeyboardShortcuts
import LaunchAtLogin

// MARK: - Inline Settings View

struct InlineSettingsView: View {
    @Environment(AppState.self) private var appState
    @Default(.voiceEngineType) private var engineType
    @Default(.murmurModel) private var murmurModel
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
                    Text("System Voices").tag(VoiceEngineType.system)
                    Text("Murmur Voice").tag(VoiceEngineType.murmur)
                }
                .pickerStyle(.segmented)
                .onChange(of: engineType) { _, newValue in
                    appState.switchEngine(to: newValue)
                }

                // Model picker (murmur only)
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

                MurmurDivider()

                // Voice selection
                if engineType == .system {
                    Text("System Default")
                        .foregroundStyle(.secondary)
                } else {
                    MurmurVoicePicker(model: murmurModel)
                }

                // Preview
                Button("Preview Voice") {
                    let voiceId = engineType == .system
                        ? Defaults[.selectedVoiceId]
                        : Defaults[.murmurVoiceId]
                    appState.previewVoice(id: voiceId)
                }
                .disabled(appState.playbackState == .speaking ||
                          (engineType == .murmur && appState.modelManager.state(for: murmurModel) != .downloaded))

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

// MARK: - Murmur Voice Picker

struct MurmurVoicePicker: View {
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

struct ModelDetailView: View {
    @Environment(AppState.self) private var appState
    let model: MurmurModel
    @State private var showDeleteConfirmation = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Languages:")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(model.supportedLanguages.joined(separator: ", "))
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Size:")
                    .foregroundStyle(.secondary)
                Spacer()
                Text(model.approxSize)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Status:")
                    .foregroundStyle(.secondary)

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

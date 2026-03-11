import SwiftUI

enum MenuBarPage {
    case main
    case settings
}

struct MenuBarView: View {
    @Environment(AppState.self) private var appState
    @State private var currentPage: MenuBarPage = .main

    var body: some View {
        Group {
            switch currentPage {
            case .main:
                mainPage
            case .settings:
                settingsPage
            }
        }
        .frame(width: 320)
        .animation(.easeInOut(duration: 0.15), value: currentPage)
    }

    // MARK: - Main Page

    private var mainPage: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            MurmurDivider()

            if appState.playbackState != .idle {
                playbackControls
                MurmurDivider()
            }

            actions
            MurmurDivider()
            footer
        }
        .padding(12)
    }

    // MARK: - Settings Page

    private var settingsPage: some View {
        VStack(alignment: .leading, spacing: 0) {
            settingsHeader
            MurmurDivider()

            ScrollView {
                InlineSettingsView()
                    .environment(appState)
            }
            .frame(maxHeight: 450)
        }
        .padding(12)
        .tint(Color.murmurAmber)
    }

    private var settingsHeader: some View {
        HStack {
            Button {
                currentPage = .main
            } label: {
                Label("Back", systemImage: "chevron.left")
                    .font(.body.weight(.medium))
            }
            .buttonStyle(.plain)
            .foregroundStyle(Color.murmurAmber)

            Spacer()

            Text("Settings")
                .font(.title3.weight(.semibold))

            Spacer()

            // Invisible balance for centering
            Label("Back", systemImage: "chevron.left")
                .font(.body.weight(.medium))
                .hidden()
        }
        .padding(.bottom, 8)
    }

    // MARK: - Main Page Sections

    private var header: some View {
        HStack {
            Image(systemName: "waveform")
                .foregroundStyle(Color.murmurAmber)
                .symbolEffect(
                    .variableColor.iterative,
                    isActive: appState.playbackState == .speaking
                )
            Text("Murmur")
                .font(.title3.weight(.semibold))
            Spacer()
            if let message = appState.statusMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var playbackControls: some View {
        HStack(spacing: 8) {
            Button {
                if appState.playbackState == .paused {
                    appState.resumePlayback()
                } else {
                    appState.pausePlayback()
                }
            } label: {
                Label(
                    appState.playbackState == .paused ? "Resume" : "Pause",
                    systemImage: appState.playbackState == .paused ? "play.fill" : "pause.fill"
                )
            }
            .buttonStyle(MurmurControlButtonStyle(tint: Color.murmurAmber))

            Button {
                appState.stopPlayback()
            } label: {
                Label("Stop", systemImage: "stop.fill")
            }
            .buttonStyle(MurmurControlButtonStyle(tint: Color.murmurEmber))

            Spacer()
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.primary.opacity(0.04))
        )
    }

    private var actions: some View {
        Button {
            appState.readClipboard()
        } label: {
            Label("Read Clipboard", systemImage: "doc.on.clipboard")
        }
        .buttonStyle(MurmurPrimaryButtonStyle())
        .keyboardShortcut("l", modifiers: [.command, .shift])
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button {
                currentPage = .settings
            } label: {
                Label("Settings...", systemImage: "gear")
            }
            .buttonStyle(MurmurMenuRowStyle())
            .keyboardShortcut(",")

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit Murmur", systemImage: "power")
            }
            .buttonStyle(MurmurMenuRowStyle())
            .keyboardShortcut("q")
        }
    }
}

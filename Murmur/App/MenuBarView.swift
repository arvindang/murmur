import SwiftUI

struct MenuBarView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            Divider()

            if appState.playbackState != .idle {
                playbackControls
                Divider()
            }

            actions
            Divider()
            footer
        }
        .padding(12)
        .frame(width: 260)
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            Image(systemName: "waveform")
            Text("Murmur")
                .font(.headline)
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

            Button {
                appState.stopPlayback()
            } label: {
                Label("Stop", systemImage: "stop.fill")
            }

            Spacer()
        }
        .buttonStyle(.bordered)
    }

    private var actions: some View {
        Button {
            appState.readClipboard()
        } label: {
            Label("Read Clipboard", systemImage: "doc.on.clipboard")
        }
        .keyboardShortcut("l", modifiers: [.command, .shift])
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                appState.openSettings()
            } label: {
                Label("Settings...", systemImage: "gear")
            }
            .keyboardShortcut(",")

            Button {
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit Murmur", systemImage: "power")
            }
            .keyboardShortcut("q")
        }
    }
}

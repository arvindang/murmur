import SwiftUI

struct MenuBarView: View {
    @Environment(AppState.self) private var appState

    var body: some View {
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
        .frame(width: 260)
    }

    // MARK: - Sections

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
            SettingsLink {
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

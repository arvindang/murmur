import SwiftUI
import KeyboardShortcuts

@main
struct MurmurApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environment(appState)
        } label: {
            Label("Murmur", systemImage: appState.menuBarIcon)
                .labelStyle(.iconOnly)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(appState)
        }
    }
}

// MARK: - App Delegate

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Reset activation policy when settings window closes
        NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.resetActivationPolicyIfNeeded()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    private func resetActivationPolicyIfNeeded() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard !AppState.isOpeningSettings else { return }
            let hasKeyWindows = NSApp.windows.contains { $0.isVisible && $0.canBecomeKey && $0.level == .normal }
            if !hasKeyWindows {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }
}

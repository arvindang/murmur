import SwiftUI
import KeyboardShortcuts

@main
struct MurmurApp: App {
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
    }
}

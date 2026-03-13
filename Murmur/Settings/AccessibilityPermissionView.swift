import SwiftUI

// MARK: - Shared Permission Monitor

struct AccessibilityPermissionMonitor: ViewModifier {
    @Binding var hasPermission: Bool
    var grantTapped: Bool

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                let newValue = AccessibilityExtractor.hasPermission
                if newValue != hasPermission { hasPermission = newValue }
            }
            .task(id: grantTapped) {
                // Fast poll for 10s after grant tap, then fall back to 2s
                if grantTapped {
                    let deadline = Date().addingTimeInterval(10)
                    while !Task.isCancelled && !hasPermission && Date() < deadline {
                        try? await Task.sleep(for: .milliseconds(500))
                        let newValue = AccessibilityExtractor.hasPermission
                        if newValue != hasPermission { hasPermission = newValue }
                    }
                }
                while !Task.isCancelled && !hasPermission {
                    try? await Task.sleep(for: .seconds(2))
                    let newValue = AccessibilityExtractor.hasPermission
                    if newValue != hasPermission { hasPermission = newValue }
                }
            }
    }
}

extension View {
    func monitorAccessibilityPermission(_ hasPermission: Binding<Bool>, grantTapped: Bool) -> some View {
        modifier(AccessibilityPermissionMonitor(hasPermission: hasPermission, grantTapped: grantTapped))
    }
}

// MARK: - Banner

struct AccessibilityPermissionBanner: View {
    @State private var hasPermission = AccessibilityExtractor.hasPermission
    @State private var grantTapped = false

    var body: some View {
        if !hasPermission {
            HStack(spacing: 8) {
                Image(systemName: "accessibility")
                    .foregroundStyle(.orange)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Accessibility Access Needed")
                        .font(.caption.weight(.semibold))
                    Text("Enable to read text from any app")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Grant Access") {
                    grantTapped = true
                    AccessibilityExtractor.openAccessibilitySettings()
                }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.orange.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.orange.opacity(0.3), lineWidth: 1)
                    )
            )
            .monitorAccessibilityPermission($hasPermission, grantTapped: grantTapped)
        }
    }
}

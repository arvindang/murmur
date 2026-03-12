import SwiftUI

struct AccessibilityPermissionBanner: View {
    @State private var hasPermission = AccessibilityExtractor.hasPermission

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
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(2))
                    hasPermission = AccessibilityExtractor.hasPermission
                    if hasPermission { break }
                }
            }
        }
    }
}

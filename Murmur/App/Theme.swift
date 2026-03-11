import SwiftUI

// MARK: - Colors

extension Color {
    static let murmurAmber = Color("MurmurAmber")
    static let murmurCopper = Color("MurmurCopper")
    static let murmurEmber = Color("MurmurEmber")
}

// MARK: - Primary Button Style

/// Full-width amber CTA button (e.g. "Read Clipboard")
struct MurmurPrimaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.murmurAmber.opacity(isEnabled ? 1 : 0.4))
            )
            .brightness(configuration.isPressed ? -0.1 : 0)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
            .onHover { hovering in
                // Hover is handled by brightness in contentShape
            }
    }
}

// MARK: - Control Button Style

/// Translucent rounded rect for playback controls (pause/resume/stop)
struct MurmurControlButtonStyle: ButtonStyle {
    var tint: Color = .murmurAmber
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(tint.opacity(isHovered ? 0.15 : 0.08))
            )
            .brightness(configuration.isPressed ? -0.1 : 0)
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

// MARK: - Menu Row Style

/// Subtle text button for footer items (Settings, Quit)
struct MurmurMenuRowStyle: ButtonStyle {
    @State private var isHovered = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body)
            .foregroundStyle(isHovered ? .primary : .secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 4)
            .padding(.horizontal, 4)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.primary.opacity(isHovered ? 0.06 : 0))
            )
            .animation(.easeOut(duration: 0.15), value: isHovered)
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

// MARK: - Section Header

/// Uppercase section label for inline settings
struct MurmurSectionHeader: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title.uppercased())
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .tracking(0.5)
    }
}

// MARK: - Divider

/// Subtle 0.5pt divider
struct MurmurDivider: View {
    var body: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.12))
            .frame(height: 0.5)
    }
}

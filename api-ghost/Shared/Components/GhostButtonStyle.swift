import SwiftUI

enum GhostButtonRole {
    case accent
    case neutral
    case destructive
}

/// Outlined action button that fills with its role color on hover. The app's single button style.
struct GhostButtonStyle: ButtonStyle {
    var role: GhostButtonRole = .accent
    var fullWidth: Bool = false

    func makeBody(configuration: Configuration) -> some View {
        GhostButtonBody(configuration: configuration, role: role, fullWidth: fullWidth)
    }

    private struct GhostButtonBody: View {
        let configuration: Configuration
        let role: GhostButtonRole
        let fullWidth: Bool

        @Environment(\.isEnabled)
        private var isEnabled
        @State private var isHovered = false

        var body: some View {
            configuration.label
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(foreground)
                .frame(maxWidth: fullWidth ? .infinity : nil)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(background)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(border, lineWidth: 1)
                )
                .opacity(isEnabled ? (configuration.isPressed ? 0.85 : 1) : 0.45)
                .onHover { isHovered = $0 }
        }

        private var foreground: Color {
            switch role {
            case .accent: return isHovered ? .ghostBase : .ghostAccentSoft
            case .neutral: return isHovered ? .ghostTextPrimary : .ghostTextSecondary
            case .destructive: return isHovered ? .white : .ghostError
            }
        }

        private var background: Color {
            switch role {
            case .accent: return isHovered ? .ghostAccentSoft : .ghostAccentMuted
            case .neutral: return isHovered ? .ghostSurfaceRaised : .clear
            case .destructive: return isHovered ? .ghostError : .clear
            }
        }

        private var border: Color {
            switch role {
            case .accent: return .ghostAccentSoft
            case .neutral: return .ghostBorder
            case .destructive: return .ghostError
            }
        }
    }
}

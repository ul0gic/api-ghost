import SwiftUI

// MARK: - Hex Initializer

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}

// MARK: - Ghost Theme Colors

extension Color {
    // MARK: - Backgrounds

    static let ghostBase = Color(hex: "#0A0A0A")

    static let ghostSurface = Color(hex: "#111111")

    static let ghostSurfaceRaised = Color(hex: "#1A1A1A")

    static let ghostSurfaceActive = Color(hex: "#242424")

    static let ghostInput = Color(hex: "#242424")

    static let ghostBorder = Color(hex: "#222222")

    // MARK: - Accent

    static let ghostAccent = Color(hex: "#00D9FF")

    static let ghostAccentHover = Color(hex: "#00B8D9")

    static let ghostAccentMuted = Color(hex: "#003844")

    // MARK: - Text

    static let ghostTextPrimary = Color(hex: "#FFFFFF")

    static let ghostTextSecondary = Color(hex: "#999999")

    static let ghostTextMuted = Color(hex: "#555555")

    // MARK: - HTTP Methods

    static let ghostMethodGet = Color(hex: "#00D9FF")

    static let ghostMethodPost = Color(hex: "#34D399")

    static let ghostMethodPut = Color(hex: "#FBBF24")

    static let ghostMethodPatch = Color(hex: "#F97316")

    static let ghostMethodDelete = Color(hex: "#EF4444")

    // MARK: - Status Codes

    static let ghostStatus2xx = Color(hex: "#34D399")

    static let ghostStatus3xx = Color(hex: "#00D9FF")

    static let ghostStatus4xx = Color(hex: "#FBBF24")

    static let ghostStatus5xx = Color(hex: "#EF4444")

    // MARK: - Semantic

    static let ghostSuccess = Color(hex: "#34D399")

    static let ghostWarning = Color(hex: "#FBBF24")

    static let ghostError = Color(hex: "#EF4444")

    // MARK: - JSON Syntax

    static let ghostJsonKey = Color(hex: "#00D9FF")

    static let ghostJsonString = Color(hex: "#34D399")

    static let ghostJsonNumber = Color(hex: "#FBBF24")

    static let ghostJsonBool = Color(hex: "#00D9FF")

    static let ghostJsonNull = Color(hex: "#EF4444")

    static let ghostJsonPunctuation = Color(hex: "#555555")
}

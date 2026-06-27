//
//  Color+Theme.swift
//  APIGhost
//
//  Ghost theme color palette for the APIGhost application.
//  All colors follow the dark-mode-only design specification.
//

import SwiftUI

// MARK: - Hex Initializer

extension Color {
    /// Creates a Color from a hex string.
    /// Supports 6-character (RGB) and 8-character (ARGB) hex strings.
    /// - Parameter hex: The hex color string (with or without # prefix)
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

    /// Main window background - #0A0A0A
    static let ghostBase = Color(hex: "#0A0A0A")

    /// Sidebar, panels - #111111
    static let ghostSurface = Color(hex: "#111111")

    /// Cards, hover states, selected rows - #1A1A1A
    static let ghostSurfaceRaised = Color(hex: "#1A1A1A")

    /// Text fields, URL bar - #0F0F0F
    static let ghostInput = Color(hex: "#0F0F0F")

    /// Dividers, outlines - #222222
    static let ghostBorder = Color(hex: "#222222")

    // MARK: - Accent

    /// Buttons, links, active states - #00D9FF (Cyan)
    static let ghostAccent = Color(hex: "#00D9FF")

    /// Hover state - #00B8D9
    static let ghostAccentHover = Color(hex: "#00B8D9")

    /// Selection backgrounds, subtle highlights - #003844
    static let ghostAccentMuted = Color(hex: "#003844")

    // MARK: - Text

    /// Headers, important text - #FFFFFF
    static let ghostTextPrimary = Color(hex: "#FFFFFF")

    /// Body text, descriptions - #999999
    static let ghostTextSecondary = Color(hex: "#999999")

    /// Disabled, placeholders, hints - #555555
    static let ghostTextMuted = Color(hex: "#555555")

    // MARK: - HTTP Methods

    /// GET method - #00D9FF (Cyan)
    static let ghostMethodGet = Color(hex: "#00D9FF")

    /// POST method - #34D399 (Green)
    static let ghostMethodPost = Color(hex: "#34D399")

    /// PUT method - #FBBF24 (Amber)
    static let ghostMethodPut = Color(hex: "#FBBF24")

    /// PATCH method - #F97316 (Orange)
    static let ghostMethodPatch = Color(hex: "#F97316")

    /// DELETE method - #EF4444 (Red)
    static let ghostMethodDelete = Color(hex: "#EF4444")

    // MARK: - Status Codes

    /// 2xx Success - #34D399 (Green)
    static let ghostStatus2xx = Color(hex: "#34D399")

    /// 3xx Redirect - #00D9FF (Cyan)
    static let ghostStatus3xx = Color(hex: "#00D9FF")

    /// 4xx Client Error - #FBBF24 (Amber)
    static let ghostStatus4xx = Color(hex: "#FBBF24")

    /// 5xx Server Error - #EF4444 (Red)
    static let ghostStatus5xx = Color(hex: "#EF4444")

    // MARK: - Semantic

    /// Confirmed, installed, complete - #34D399 (Green)
    static let ghostSuccess = Color(hex: "#34D399")

    /// Attention needed, caution - #FBBF24 (Amber)
    static let ghostWarning = Color(hex: "#FBBF24")

    /// Failed, destructive actions - #EF4444 (Red)
    static let ghostError = Color(hex: "#EF4444")

    // MARK: - JSON Syntax

    /// JSON keys - #00D9FF (Cyan)
    static let ghostJsonKey = Color(hex: "#00D9FF")

    /// JSON string values - #34D399 (Green)
    static let ghostJsonString = Color(hex: "#34D399")

    /// JSON number values - #FBBF24 (Amber)
    static let ghostJsonNumber = Color(hex: "#FBBF24")

    /// JSON boolean values - #00D9FF (Cyan)
    static let ghostJsonBool = Color(hex: "#00D9FF")

    /// JSON null values - #EF4444 (Red)
    static let ghostJsonNull = Color(hex: "#EF4444")

    /// JSON punctuation (braces, brackets, colons, commas) - #555555
    static let ghostJsonPunctuation = Color(hex: "#555555")
}

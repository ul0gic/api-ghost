//
//  MapBadges.swift
//  APIGhost
//
//  Badge views used in the API Map: method badges, status code badges, parameter badges.
//

import SwiftUI

// MARK: - Map Method Badge

struct MapMethodBadge: View {
    let method: String
    let size: BadgeSize

    enum BadgeSize {
        case tiny, small, normal

        var fontSize: CGFloat {
            switch self {
            case .tiny: return 7
            case .small: return 8
            case .normal: return 9
            }
        }

        var padding: (horizontal: CGFloat, vertical: CGFloat) {
            switch self {
            case .tiny: return (3, 1)
            case .small: return (4, 2)
            case .normal: return (6, 2)
            }
        }
    }

    var body: some View {
        Text(method)
            .font(.system(size: size.fontSize, weight: .bold, design: .monospaced))
            .foregroundColor(methodColor)
            .padding(.horizontal, size.padding.horizontal)
            .padding(.vertical, size.padding.vertical)
            .background(methodColor.opacity(0.15))
            .cornerRadius(3)
    }

    private var methodColor: Color {
        switch method.uppercased() {
        case "GET": return .ghostMethodGet
        case "POST": return .ghostMethodPost
        case "PUT": return .ghostMethodPut
        case "PATCH": return .ghostMethodPatch
        case "DELETE": return .ghostMethodDelete
        default: return .ghostTextMuted
        }
    }
}

// MARK: - Status Code Badge

struct StatusCodeBadge: View {
    let code: Int

    var body: some View {
        Text("\(code)")
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundColor(statusColor)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(statusColor.opacity(0.15))
            .cornerRadius(3)
    }

    private var statusColor: Color {
        switch code {
        case 200..<300: return .ghostStatus2xx
        case 300..<400: return .ghostStatus3xx
        case 400..<500: return .ghostStatus4xx
        case 500..<600: return .ghostStatus5xx
        default: return .ghostTextMuted
        }
    }
}

// MARK: - Parameter Badge

struct ParameterBadge: View {
    let type: ParameterType

    var body: some View {
        Text(type.placeholder)
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundColor(type.color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(type.color.opacity(0.15))
            .cornerRadius(4)
            .help(type.description)
    }
}

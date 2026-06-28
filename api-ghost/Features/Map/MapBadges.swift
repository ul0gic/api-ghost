import SwiftUI

// MARK: - Status Palette

enum MapStatusPalette {
    static func color(for code: Int) -> Color {
        switch code {
        case 200..<300: return .ghostStatus2xx
        case 300..<400: return .ghostStatus3xx
        case 400..<500: return .ghostStatus4xx
        case 500..<600: return .ghostStatus5xx
        default: return .ghostTextMuted
        }
    }
}

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

// MARK: - Status Rollup Chips

struct StatusRollupChips: View {
    let counts: [(code: Int, count: Int)]
    var limit: Int = 4

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(counts.prefix(limit)), id: \.code) { entry in
                let color = MapStatusPalette.color(for: entry.code)
                Text("\(entry.code) ×\(entry.count)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(color)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(color.opacity(0.1))
                    .cornerRadius(3)
            }
            if counts.count > limit {
                Text("+\(counts.count - limit)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.ghostTextMuted)
            }
        }
    }
}

// MARK: - Op Method Badge

struct OpMethodBadge: View {
    let method: String

    var body: some View {
        Text(method)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundColor(methodColor)
            .frame(width: 44)
            .padding(.vertical, 2)
            .background(methodColor.opacity(0.08))
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

// MARK: - GraphQL Op Type Badge

struct GraphQLOpTypeBadge: View {
    let type: GraphQLOperationType

    var body: some View {
        Text(type.label)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundColor(type.color)
            .frame(width: 72)
            .padding(.vertical, 2)
            .background(type.color.opacity(0.08))
            .cornerRadius(3)
    }
}

// MARK: - Parameterized Path Text

struct ParameterizedPathText: View {
    let path: String

    var body: some View {
        Text(attributedPath)
            .font(.system(size: 12, design: .monospaced))
            .lineLimit(1)
    }

    private var attributedPath: AttributedString {
        var result = AttributedString()
        for segment in segments {
            var piece = AttributedString(segment.text)
            piece.foregroundColor = segment.isParameter ? .ghostWarning : .ghostTextPrimary
            result.append(piece)
        }
        return result
    }

    private var segments: [(text: String, isParameter: Bool)] {
        var result: [(String, Bool)] = []
        var buffer = ""
        var insideParam = false

        for character in path {
            if character == "{" {
                if !buffer.isEmpty { result.append((buffer, false)); buffer = "" }
                buffer.append(character)
                insideParam = true
            } else if character == "}" {
                buffer.append(character)
                result.append((buffer, true))
                buffer = ""
                insideParam = false
            } else {
                buffer.append(character)
            }
        }
        if !buffer.isEmpty { result.append((buffer, insideParam)) }
        return result.map { (text: $0.0, isParameter: $0.1) }
    }
}

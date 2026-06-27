//
//  JSONViewer.swift
//  api-ghost
//
//  JSON viewer with syntax highlighting
//

import SwiftUI

// MARK: - JSON Viewer

struct JSONViewer: View {
    let jsonString: String
    @State private var isExpanded: Bool = true

    var body: some View {
        ScrollView([.horizontal, .vertical], showsIndicators: true) {
            if let formattedText = parseAndHighlight(jsonString) {
                Text(formattedText)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(10)
            } else {
                // Fallback to plain text
                Text(jsonString)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.ghostTextSecondary)
                    .textSelection(.enabled)
                    .padding(10)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - JSON Parsing and Highlighting

    private func parseAndHighlight(_ json: String) -> AttributedString? {
        // Try to parse and pretty print
        guard let data = json.data(using: .utf8) else { return nil }

        let prettyJSON: String
        do {
            let jsonObject = try JSONSerialization.jsonObject(with: data, options: [])
            let prettyData = try JSONSerialization.data(
                withJSONObject: jsonObject,
                options: [.prettyPrinted, .sortedKeys]
            )
            prettyJSON = String(data: prettyData, encoding: .utf8) ?? json
        } catch {
            // If parsing fails, use original string
            prettyJSON = json
        }

        return highlightJSON(prettyJSON)
    }

    private func highlightJSON(_ json: String) -> AttributedString {
        var result = AttributedString()
        var index = json.startIndex
        let end = json.endIndex

        while index < end {
            let char = json[index]

            switch char {
            case "\"":
                index = highlightString(in: json, at: index, into: &result)
            case "{", "}", "[", "]", ":", ",":
                appendColored(String(char), color: .ghostJsonPunctuation, to: &result)
                index = json.index(after: index)
            case "0"..."9", "-", ".":
                index = highlightNumber(in: json, at: index, into: &result)
            case "t", "f":
                index = highlightBoolLiteral(in: json, at: index, into: &result)
            case "n":
                index = highlightNullLiteral(in: json, at: index, into: &result)
            default:
                appendColored(String(char), color: .ghostTextSecondary, to: &result)
                index = json.index(after: index)
            }
        }

        return result
    }

    private func appendColored(_ text: String, color: Color, to result: inout AttributedString) {
        var attrString = AttributedString(text)
        attrString.foregroundColor = color
        result.append(attrString)
    }

    private func highlightString(
        in json: String, at index: String.Index, into result: inout AttributedString
    ) -> String.Index {
        if let stringEnd = findStringEnd(in: json, from: index) {
            let stringContent = String(json[index...stringEnd])
            let nextNonWhitespace = findNextNonWhitespace(in: json, from: json.index(after: stringEnd))
            let isKey = nextNonWhitespace.map { json[$0] == ":" } ?? false
            appendColored(stringContent, color: isKey ? .ghostJsonKey : .ghostJsonString, to: &result)
            return json.index(after: stringEnd)
        } else {
            appendColored(String(json[index]), color: .ghostTextSecondary, to: &result)
            return json.index(after: index)
        }
    }

    private func highlightNumber(
        in json: String, at index: String.Index, into result: inout AttributedString
    ) -> String.Index {
        let numberStr = extractNumber(from: json, startingAt: index)
        appendColored(numberStr, color: .ghostJsonNumber, to: &result)
        return json.index(index, offsetBy: numberStr.count)
    }

    private func highlightBoolLiteral(
        in json: String, at index: String.Index, into result: inout AttributedString
    ) -> String.Index {
        let remaining = String(json[index...])
        if remaining.hasPrefix("true") {
            appendColored("true", color: .ghostJsonBool, to: &result)
            return json.index(index, offsetBy: 4)
        } else if remaining.hasPrefix("false") {
            appendColored("false", color: .ghostJsonBool, to: &result)
            return json.index(index, offsetBy: 5)
        } else {
            appendColored(String(json[index]), color: .ghostTextSecondary, to: &result)
            return json.index(after: index)
        }
    }

    private func highlightNullLiteral(
        in json: String, at index: String.Index, into result: inout AttributedString
    ) -> String.Index {
        let remaining = String(json[index...])
        if remaining.hasPrefix("null") {
            appendColored("null", color: .ghostJsonNull, to: &result)
            return json.index(index, offsetBy: 4)
        } else {
            appendColored(String(json[index]), color: .ghostTextSecondary, to: &result)
            return json.index(after: index)
        }
    }

    private func findStringEnd(in json: String, from start: String.Index) -> String.Index? {
        guard json[start] == "\"" else { return nil }

        var index = json.index(after: start)
        while index < json.endIndex {
            let char = json[index]
            if char == "\\" && json.index(after: index) < json.endIndex {
                // Skip escaped character
                index = json.index(index, offsetBy: 2)
            } else if char == "\"" {
                return index
            } else {
                index = json.index(after: index)
            }
        }
        return nil
    }

    private func findNextNonWhitespace(in json: String, from start: String.Index) -> String.Index? {
        var index = start
        while index < json.endIndex {
            let char = json[index]
            if !char.isWhitespace {
                return index
            }
            index = json.index(after: index)
        }
        return nil
    }

    private func extractNumber(from json: String, startingAt start: String.Index) -> String {
        var index = start
        var numberStr = ""

        while index < json.endIndex {
            let char = json[index]
            if char.isNumber || char == "-" || char == "." || char == "e" || char == "E" || char == "+" {
                numberStr.append(char)
                index = json.index(after: index)
            } else {
                break
            }
        }

        return numberStr
    }
}

// MARK: - Compact JSON Viewer

struct CompactJSONViewer: View {
    let jsonString: String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Text(compactJSON)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.ghostTextSecondary)
                .textSelection(.enabled)
                .lineLimit(1)
        }
    }

    private var compactJSON: String {
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data),
              let compact = try? JSONSerialization.data(withJSONObject: json),
              let str = String(data: compact, encoding: .utf8) else {
            return jsonString
        }
        return str
    }
}

// MARK: - Preview

#Preview {
    JSONViewer(jsonString: """
    {
        "id": 123,
        "name": "John Doe",
        "email": "john@example.com",
        "roles": ["admin", "user"],
        "metadata": {
            "lastLogin": "2024-01-15T10:30:00Z",
            "preferences": {
                "theme": "dark",
                "notifications": true
            }
        },
        "active": true,
        "score": 42.5,
        "avatar": null
    }
    """)
    .preferredColorScheme(.dark)
    .frame(width: 400, height: 300)
    .background(Color.ghostBase)
}

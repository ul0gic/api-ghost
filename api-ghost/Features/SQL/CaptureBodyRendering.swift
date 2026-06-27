import SwiftUI

// MARK: - Body Format

enum CaptureBodyFormat: Equatable {
    case json
    case formURLEncoded
    case multipart(boundary: String)
    case text
    case binary

    init(contentType: String?, data: Data) {
        let type = contentType?.lowercased() ?? ""

        if type.contains("json") {
            self = .json
        } else if type.contains("x-www-form-urlencoded") {
            self = .formURLEncoded
        } else if type.contains("multipart/form-data"), let boundary = Self.boundary(in: type) {
            self = .multipart(boundary: boundary)
        } else if type.isEmpty {
            self = Self.sniff(data)
        } else if type.hasPrefix("text/") || type.contains("xml") || type.contains("html") {
            self = .text
        } else {
            self = Self.sniff(data)
        }
    }

    private static func sniff(_ data: Data) -> CaptureBodyFormat {
        guard let text = String(data: data, encoding: .utf8) else { return .binary }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") { return .json }
        return .text
    }

    private static func boundary(in contentType: String) -> String? {
        guard let range = contentType.range(of: "boundary=") else { return nil }
        let raw = contentType[range.upperBound...]
        let value = raw.split(separator: ";").first.map(String.init) ?? String(raw)
        return value.trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
    }

    var label: String {
        switch self {
        case .json: return "application/json"
        case .formURLEncoded: return "x-www-form-urlencoded"
        case .multipart: return "multipart/form-data"
        case .text: return "text"
        case .binary: return "binary"
        }
    }
}

// MARK: - Decoded Body View

struct DecodedBodyView: View {
    let data: Data
    let contentType: String?

    private var format: CaptureBodyFormat { CaptureBodyFormat(contentType: contentType, data: data) }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("decoded · \(format.label)")
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(.ghostTextMuted)
                .tracking(0.5)

            content
        }
    }

    @ViewBuilder private var content: some View {
        switch format {
        case .json:
            if let text = String(data: data, encoding: .utf8) {
                JSONViewer(jsonString: text)
            } else {
                RawCaptureBodyView(data: data)
            }
        case .formURLEncoded:
            FormURLEncodedView(data: data)
        case .multipart(let boundary):
            MultipartBodyView(data: data, boundary: boundary)
        case .text:
            RawCaptureBodyView(data: data)
        case .binary:
            HexDumpView(data: data)
        }
    }
}

// MARK: - Form URL-Encoded

struct FormURLEncodedView: View {
    let data: Data

    private var pairs: [(key: String, value: String)] {
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        return text.split(separator: "&").map { component in
            let parts = component.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let key = Self.decode(String(parts.first ?? ""))
            let value = parts.count > 1 ? Self.decode(String(parts[1])) : ""
            return (key, value)
        }
    }

    var body: some View {
        if pairs.isEmpty {
            RawCaptureBodyView(data: data)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(pairs.enumerated()), id: \.offset) { _, pair in
                    HStack(alignment: .top, spacing: 6) {
                        Text(pair.key)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.ghostJsonKey)
                        Text("=")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.ghostJsonPunctuation)
                        Text(pair.value)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.ghostJsonString)
                            .textSelection(.enabled)
                    }
                }
            }
        }
    }

    private static func decode(_ value: String) -> String {
        value.replacingOccurrences(of: "+", with: " ").removingPercentEncoding ?? value
    }
}

// MARK: - Multipart

struct MultipartBodyView: View {
    let data: Data
    let boundary: String

    var body: some View {
        if parts.isEmpty {
            RawCaptureBodyView(data: data)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
                    VStack(alignment: .leading, spacing: 3) {
                        Text("part \(index + 1)\(part.contentType.map { " · \($0)" } ?? "")")
                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                            .foregroundColor(.ghostAccent)
                        ForEach(part.headers, id: \.self) { header in
                            Text(header)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.ghostTextMuted)
                        }
                        if !part.body.isEmpty {
                            Text(part.body)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.ghostTextSecondary)
                                .textSelection(.enabled)
                        }
                    }
                    .padding(.bottom, 2)
                }
            }
        }
    }

    private struct Part {
        let headers: [String]
        let contentType: String?
        let body: String
    }

    private var parts: [Part] {
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        let segments = text.components(separatedBy: "--\(boundary)")
        return segments.compactMap { segment -> Part? in
            let trimmed = segment.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, trimmed != "--" else { return nil }
            let blocks = segment.components(separatedBy: "\r\n\r\n")
            let headerBlock = blocks.first ?? ""
            let headers = headerBlock
                .components(separatedBy: "\r\n")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            guard !headers.isEmpty else { return nil }
            let contentType = Self.partContentType(in: headers)
            let joined = blocks.dropFirst().joined(separator: "\r\n\r\n")
            let bodyText = joined.trimmingCharacters(in: .whitespacesAndNewlines)
            let preview = bodyText.count > 500 ? String(bodyText.prefix(500)) + "…" : bodyText
            return Part(headers: headers, contentType: contentType, body: preview)
        }
    }

    private static func partContentType(in headers: [String]) -> String? {
        guard let header = headers.first(where: { $0.lowercased().hasPrefix("content-type:") }) else {
            return nil
        }
        let stripped = header.replacingOccurrences(of: "Content-Type:", with: "", options: .caseInsensitive)
        return stripped.trimmingCharacters(in: .whitespaces)
    }
}

// MARK: - Hex Dump

struct HexDumpView: View {
    let data: Data

    private static let maxBytes = 2048

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ScrollView([.horizontal, .vertical], showsIndicators: true) {
                Text(hexDump)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.ghostTextSecondary)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 300)

            if data.count > Self.maxBytes {
                Text("… \(data.count - Self.maxBytes) more bytes")
                    .font(.system(size: 10))
                    .foregroundColor(.ghostTextMuted)
            }
        }
    }

    private var hexDump: String {
        let slice = Array(data.prefix(Self.maxBytes))
        var lines: [String] = []
        for chunk in stride(from: 0, to: slice.count, by: 16) {
            let bytes = Array(slice[chunk..<min(chunk + 16, slice.count)])
            let hex = bytes.map { String(format: "%02x", $0) }
                .joined(separator: " ")
                .padding(toLength: 47, withPad: " ", startingAt: 0)
            let ascii = bytes.map { $0 >= 32 && $0 <= 126 ? String(UnicodeScalar($0)) : "." }.joined()
            lines.append("\(String(format: "%08x", chunk))  \(hex)  \(ascii)")
        }
        return lines.joined(separator: "\n")
    }
}

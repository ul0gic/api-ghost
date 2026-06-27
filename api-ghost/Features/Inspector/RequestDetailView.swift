//
//  RequestDetailView.swift
//  api-ghost
//
//  Displays request details including method, path, headers, and body
//

import SwiftUI

// MARK: - Request Detail View

struct RequestDetailView: View {
    let capture: Capture

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Request line
                RequestLineView(capture: capture)

                Divider()
                    .background(Color.ghostBorder)

                // Headers section
                if let headers = capture.requestHeadersDictionary, !headers.isEmpty {
                    DetailSection(title: "HEADERS") {
                        HeadersView(headers: headers)
                    }
                }

                // Body section
                if let body = capture.requestBody, !body.isEmpty {
                    DetailSection(title: "BODY") {
                        BodyView(data: body, contentType: getRequestContentType())
                    }
                }

                Spacer()
            }
            .padding(12)
        }
        .background(Color.ghostSurface)
    }

    private func getRequestContentType() -> String? {
        guard let headers = capture.requestHeadersDictionary else { return nil }
        return headers.first { $0.key.lowercased() == "content-type" }?.value
    }
}

// MARK: - Request Line View

struct RequestLineView: View {
    let capture: Capture

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                MethodBadge(method: capture.method)

                Text(capture.fullURL)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.ghostTextPrimary)
                    .lineLimit(2)
                    .textSelection(.enabled)
            }

            if let duration = capture.durationMs {
                HStack(spacing: 16) {
                    DetailLabel(label: "Duration", value: "\(duration)ms")
                    DetailLabel(label: "Size", value: formatSize(capture.requestBodySize))
                }
            }
        }
    }

    private func formatSize(_ bytes: Int) -> String {
        if bytes == 0 { return "0B" }
        if bytes < 1024 { return "\(bytes)B" }
        if bytes < 1024 * 1024 { return String(format: "%.1fK", Double(bytes) / 1024) }
        return String(format: "%.1fM", Double(bytes) / (1024 * 1024))
    }
}

// MARK: - Detail Section

struct DetailSection<Content: View>: View {
    let title: String
    let content: () -> Content

    init(title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.ghostTextMuted)
                .tracking(1)

            content()
        }
    }
}

// MARK: - Detail Label

struct DetailLabel: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 4) {
            Text(label + ":")
                .font(.system(size: 11))
                .foregroundColor(.ghostTextMuted)

            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.ghostTextSecondary)
        }
    }
}

// MARK: - Headers View

struct HeadersView: View {
    let headers: [String: String]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(headers.sorted { $0.key < $1.key }, id: \.key) { key, value in
                HStack(alignment: .top, spacing: 4) {
                    Text(key + ":")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.ghostAccent)

                    Text(value)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.ghostTextSecondary)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.ghostBase)
        .cornerRadius(6)
    }
}

// MARK: - Body View

struct BodyView: View {
    let data: Data
    let contentType: String?

    var body: some View {
        Group {
            if isJSON {
                if let text = String(data: data, encoding: .utf8) {
                    JSONViewer(jsonString: text)
                } else {
                    RawBodyView(data: data)
                }
            } else {
                RawBodyView(data: data)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.ghostBase)
        .cornerRadius(6)
    }

    private var isJSON: Bool {
        guard let contentType = contentType?.lowercased() else {
            // Try to detect JSON from content
            if let text = String(data: data, encoding: .utf8) {
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.hasPrefix("{") || trimmed.hasPrefix("[")
            }
            return false
        }
        return contentType.contains("json")
    }
}

// MARK: - Raw Body View

struct RawBodyView: View {
    let data: Data

    var body: some View {
        if let text = String(data: data, encoding: .utf8) {
            ScrollView(.horizontal, showsIndicators: false) {
                Text(text)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.ghostTextSecondary)
                    .textSelection(.enabled)
                    .padding(10)
            }
        } else {
            Text("Binary data (\(data.count) bytes)")
                .font(.system(size: 11))
                .foregroundColor(.ghostTextMuted)
                .padding(10)
        }
    }
}

// MARK: - Preview

#Preview {
    RequestDetailView(
        capture: Capture(
            method: "POST",
            scheme: "https",
            host: "api.example.com",
            path: "/users",
            requestHeaders: """
            {"Authorization": "Bearer token123", "Content-Type": "application/json"}
            """,
            requestBody: Data("{\"name\": \"John Doe\", \"email\": \"john@example.com\", \"age\": 30}".utf8),
            requestBodySize: 58,
            durationMs: 145
        )
    )
    .preferredColorScheme(.dark)
    .frame(width: 600, height: 400)
}

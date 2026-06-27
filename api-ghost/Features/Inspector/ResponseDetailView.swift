import SwiftUI

// MARK: - Response Detail View

struct ResponseDetailView: View {
    let capture: Capture

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ResponseStatusView(capture: capture)

                Divider()
                    .background(Color.ghostBorder)

                if let headers = capture.responseHeadersDictionary, !headers.isEmpty {
                    DetailSection(title: "HEADERS") {
                        HeadersView(headers: headers)
                    }
                }

                if let body = capture.responseBody, !body.isEmpty {
                    DetailSection(title: "BODY") {
                        BodyView(data: body, contentType: capture.contentType)
                    }
                } else {
                    DetailSection(title: "BODY") {
                        Text("No response body")
                            .font(.system(size: 11))
                            .foregroundColor(.ghostTextMuted)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.ghostBase)
                            .cornerRadius(6)
                    }
                }

                Spacer()
            }
            .padding(12)
        }
        .background(Color.ghostSurface)
    }
}

// MARK: - Response Status View

struct ResponseStatusView: View {
    let capture: Capture

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                if let status = capture.statusCode {
                    StatusBadgeLarge(statusCode: status, statusMessage: capture.statusMessage)
                } else {
                    Text("No Response")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.ghostTextMuted)
                }
            }

            HStack(spacing: 16) {
                if let contentType = capture.contentType {
                    DetailLabel(label: "Content-Type", value: contentType)
                }
                DetailLabel(label: "Size", value: formatSize(capture.responseBodySize))
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

// MARK: - Status Badge Large

struct StatusBadgeLarge: View {
    let statusCode: Int
    let statusMessage: String?

    var body: some View {
        HStack(spacing: 8) {
            Text("\(statusCode)")
                .font(.system(size: 16, weight: .bold, design: .monospaced))
                .foregroundColor(statusColor)

            if let message = statusMessage {
                Text(message)
                    .font(.system(size: 14))
                    .foregroundColor(.ghostTextSecondary)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(statusColor.opacity(0.15))
        .cornerRadius(6)
    }

    private var statusColor: Color {
        switch statusCode {
        case 200..<300: return .ghostStatus2xx
        case 300..<400: return .ghostStatus3xx
        case 400..<500: return .ghostStatus4xx
        case 500..<600: return .ghostStatus5xx
        default: return .ghostTextSecondary
        }
    }
}

// MARK: - Preview

#Preview {
    ResponseDetailView(
        capture: Capture(
            method: "GET",
            scheme: "https",
            host: "api.example.com",
            path: "/users/123",
            statusCode: 200,
            statusMessage: "OK",
            responseHeaders: """
            {"Content-Type": "application/json", "Cache-Control": "no-cache", "X-Request-Id": "abc123"}
            """,
            responseBody: Data("""
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
            """.utf8),
            responseBodySize: 312,
            contentType: "application/json"
        )
    )
    .preferredColorScheme(.dark)
    .frame(width: 600, height: 500)
}

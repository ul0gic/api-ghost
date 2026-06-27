//
//  SQLCaptureComponents.swift
//  APIGhost
//
//  Reusable UI components for SQL capture detail views.
//

import SwiftUI

// MARK: - Metadata Row

struct MetadataRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.ghostTextMuted)
                .frame(width: 100, alignment: .leading)

            Text(value)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.ghostTextPrimary)
                .textSelection(.enabled)
        }
    }
}

// MARK: - Detail Card

struct CaptureDetailCard<Content: View>: View {
    let title: String
    var copyAction: (() -> Void)?
    @Binding var copiedItem: String?
    var itemId: String?
    let content: () -> Content

    init(
        title: String,
        copyAction: (() -> Void)? = nil,
        copiedItem: Binding<String?> = .constant(nil),
        itemId: String? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.copyAction = copyAction
        self._copiedItem = copiedItem
        self.itemId = itemId
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.ghostTextMuted)
                    .tracking(1)

                Spacer()

                if let copyAction = copyAction {
                    Button(action: copyAction) {
                        HStack(spacing: 4) {
                            Image(systemName: copiedItem == itemId ? "checkmark" : "doc.on.doc")
                                .font(.system(size: 10))
                            Text(copiedItem == itemId ? "Copied" : "Copy")
                                .font(.system(size: 10))
                        }
                        .foregroundColor(copiedItem == itemId ? .ghostSuccess : .ghostTextSecondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.ghostSurfaceRaised)
                        .cornerRadius(4)
                    }
                    .buttonStyle(.plain)
                }
            }

            content()
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.ghostInput)
                .cornerRadius(6)
        }
    }
}

// MARK: - Headers View

struct CaptureHeadersView: View {
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
    }
}

// MARK: - Body View

struct CaptureBodyView: View {
    let data: Data
    let contentType: String?

    var body: some View {
        Group {
            if isJSON {
                if let text = String(data: data, encoding: .utf8) {
                    JSONViewer(jsonString: text)
                } else {
                    RawCaptureBodyView(data: data)
                }
            } else {
                RawCaptureBodyView(data: data)
            }
        }
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

struct RawCaptureBodyView: View {
    let data: Data

    var body: some View {
        if let text = String(data: data, encoding: .utf8) {
            ScrollView([.horizontal, .vertical], showsIndicators: true) {
                Text(text)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.ghostTextSecondary)
                    .textSelection(.enabled)
            }
            .frame(maxHeight: 300)
        } else {
            Text("Binary data (\(data.count) bytes)")
                .font(.system(size: 11))
                .foregroundColor(.ghostTextMuted)
        }
    }
}

// MARK: - Copy Button

struct CopyButton: View {
    let title: String
    let icon: String
    let itemId: String
    @Binding var copiedItem: String?
    let action: () -> Void

    var body: some View {
        Button(action: {
            action()
            copiedItem = itemId
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                if copiedItem == itemId { copiedItem = nil }
            }
        }, label: {
            HStack(spacing: 4) {
                Image(systemName: copiedItem == itemId ? "checkmark" : icon)
                    .font(.system(size: 10))
                Text(copiedItem == itemId ? "Copied" : title)
                    .font(.system(size: 11))
            }
            .foregroundColor(copiedItem == itemId ? .ghostSuccess : .ghostTextSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.ghostSurfaceRaised)
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.ghostBorder, lineWidth: 1)
            )
        })
        .buttonStyle(.plain)
    }
}

// MARK: - Footer

struct CaptureDetailFooter: View {
    let capture: Capture
    @Binding var copiedItem: String?

    var body: some View {
        HStack(spacing: 12) {
            CopyButton(
                title: "Copy URL",
                icon: "link",
                itemId: "url",
                copiedItem: $copiedItem
            ) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(capture.fullURL, forType: .string)
            }

            CopyButton(
                title: "Copy cURL",
                icon: "terminal",
                itemId: "curl",
                copiedItem: $copiedItem
            ) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(generateCurlCommand(), forType: .string)
            }

            CopyButton(
                title: "Copy as JSON",
                icon: "curlybraces",
                itemId: "json",
                copiedItem: $copiedItem
            ) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(generateJSON(), forType: .string)
            }

            Spacer()
        }
        .padding(12)
        .background(Color.ghostSurface)
    }

    private func generateCurlCommand() -> String {
        var command = "curl"

        if capture.method != "GET" {
            command += " -X \(capture.method)"
        }

        command += " '\(capture.fullURL)'"

        if let headers = capture.requestHeadersDictionary {
            for (key, value) in headers.sorted(by: { $0.key < $1.key }) {
                if ["host", "content-length", "accept-encoding"].contains(key.lowercased()) {
                    continue
                }
                let escapedValue = value.replacingOccurrences(of: "'", with: "'\\''")
                command += " \\\n  -H '\(key): \(escapedValue)'"
            }
        }

        if let body = capture.requestBody,
           let bodyString = String(data: body, encoding: .utf8) {
            let escapedBody = bodyString.replacingOccurrences(of: "'", with: "'\\''")
            command += " \\\n  --data '\(escapedBody)'"
        }

        return command
    }

    private func generateJSON() -> String {
        var dict: [String: Any] = [
            "method": capture.method,
            "url": capture.fullURL,
            "host": capture.host,
            "path": capture.path,
            "timestamp": ISO8601DateFormatter().string(from: capture.timestamp)
        ]

        if let statusCode = capture.statusCode {
            dict["statusCode"] = statusCode
        }
        if let statusMessage = capture.statusMessage {
            dict["statusMessage"] = statusMessage
        }
        if let duration = capture.durationMs {
            dict["durationMs"] = duration
        }
        if let contentType = capture.contentType {
            dict["contentType"] = contentType
        }
        if let headers = capture.requestHeadersDictionary {
            dict["requestHeaders"] = headers
        }
        if let headers = capture.responseHeadersDictionary {
            dict["responseHeaders"] = headers
        }
        if let body = capture.requestBody,
           let text = String(data: body, encoding: .utf8) {
            dict["requestBody"] = text
        }
        if let body = capture.responseBody,
           let text = String(data: body, encoding: .utf8) {
            dict["responseBody"] = text
        }

        if let data = try? JSONSerialization.data(
            withJSONObject: dict,
            options: .prettyPrinted
        ),
           let string = String(data: data, encoding: .utf8) {
            return string
        }
        return "{}"
    }
}

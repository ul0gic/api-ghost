//
//  SQLCaptureDetailView.swift
//  APIGhost
//
//  Full capture detail modal for SQL query results - shows request/response details with copy functionality.
//

import SwiftUI

// MARK: - SQL Capture Detail View

struct SQLCaptureDetailView: View {
    let capture: Capture
    let onClose: () -> Void

    @State private var selectedTab: CaptureDetailTab = .request
    @State private var copiedItem: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            CaptureDetailHeader(capture: capture, onClose: onClose)

            Divider()
                .background(Color.ghostBorder)

            // Tab bar
            CaptureDetailTabBar(selectedTab: $selectedTab)

            Divider()
                .background(Color.ghostBorder)

            // Content
            ScrollView {
                Group {
                    switch selectedTab {
                    case .request:
                        RequestSection(capture: capture, copiedItem: $copiedItem)
                    case .response:
                        ResponseSection(capture: capture, copiedItem: $copiedItem)
                    case .metadata:
                        MetadataSection(capture: capture, copiedItem: $copiedItem)
                    }
                }
                .padding(16)
            }

            Divider()
                .background(Color.ghostBorder)

            // Footer with copy actions
            CaptureDetailFooter(capture: capture, copiedItem: $copiedItem)
        }
        .frame(width: 700, height: 600)
        .background(Color.ghostBase)
    }
}

// MARK: - Detail Tabs

enum CaptureDetailTab: String, CaseIterable {
    case request = "Request"
    case response = "Response"
    case metadata = "Metadata"
}

// MARK: - Header

struct CaptureDetailHeader: View {
    let capture: Capture
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Method badge
            MethodBadge(method: capture.method)

            // Status badge
            if let status = capture.statusCode {
                StatusBadge(statusCode: status)
            }

            // URL
            VStack(alignment: .leading, spacing: 2) {
                Text(capture.host)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.ghostTextPrimary)

                Text(capture.path)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.ghostTextSecondary)
                    .lineLimit(1)
            }

            Spacer()

            // Close button
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.ghostTextSecondary)
                    .frame(width: 28, height: 28)
                    .background(Color.ghostSurfaceRaised)
                    .cornerRadius(6)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
        }
        .padding(16)
        .background(Color.ghostSurface)
    }
}

// MARK: - Tab Bar

struct CaptureDetailTabBar: View {
    @Binding var selectedTab: CaptureDetailTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(CaptureDetailTab.allCases, id: \.self) { tab in
                Button(action: { selectedTab = tab }, label: {
                    Text(tab.rawValue)
                        .font(.system(size: 12, weight: selectedTab == tab ? .semibold : .regular))
                        .foregroundColor(selectedTab == tab ? .ghostAccent : .ghostTextSecondary)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(selectedTab == tab ? Color.ghostAccentMuted : Color.clear)
                        .cornerRadius(4)
                })
                .buttonStyle(.plain)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.ghostSurface)
    }
}

// MARK: - Request Section

struct RequestSection: View {
    let capture: Capture
    @Binding var copiedItem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Request line
            CaptureDetailCard(title: "Request Line") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        MethodBadge(method: capture.method)
                        Text(capture.fullURL)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundColor(.ghostTextPrimary)
                            .textSelection(.enabled)
                    }
                }
            }

            // Headers
            if let headers = capture.requestHeadersDictionary, !headers.isEmpty {
                CaptureDetailCard(
                    title: "Headers",
                    copyAction: headersCopyAction(headers),
                    copiedItem: $copiedItem,
                    itemId: "request_headers"
                ) {
                    CaptureHeadersView(headers: headers)
                }
            }

            // Body
            if let body = capture.requestBody, !body.isEmpty {
                CaptureDetailCard(
                    title: "Body (\(formatBytes(body.count)))",
                    copyAction: bodyCopyAction(body),
                    copiedItem: $copiedItem,
                    itemId: "request_body"
                ) {
                    CaptureBodyView(
                        data: body,
                        contentType: getRequestContentType()
                    )
                }
            } else {
                CaptureDetailCard(title: "Body") {
                    Text("No request body")
                        .font(.system(size: 12))
                        .foregroundColor(.ghostTextMuted)
                }
            }
        }
    }

    private func headersCopyAction(_ headers: [String: String]) -> () -> Void {
        { [self] in copyHeaders(headers) }
    }

    private func bodyCopyAction(_ body: Data) -> () -> Void {
        { [self] in copyBody(body) }
    }

    private func getRequestContentType() -> String? {
        guard let headers = capture.requestHeadersDictionary else { return nil }
        return headers.first { $0.key.lowercased() == "content-type" }?.value
    }

    private func copyHeaders(_ headers: [String: String]) {
        let text = headers.sorted { $0.key < $1.key }
            .map { "\($0.key): \($0.value)" }
            .joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copiedItem = "request_headers"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if copiedItem == "request_headers" { copiedItem = nil }
        }
    }

    private func copyBody(_ data: Data) {
        if let text = String(data: data, encoding: .utf8) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            copiedItem = "request_body"
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                if copiedItem == "request_body" { copiedItem = nil }
            }
        }
    }

    private func formatBytes(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return String(format: "%.1f KB", Double(bytes) / 1024) }
        return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
    }
}

// MARK: - Response Section

struct ResponseSection: View {
    let capture: Capture
    @Binding var copiedItem: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Status line
            CaptureDetailCard(title: "Status") {
                HStack(spacing: 12) {
                    if let status = capture.statusCode {
                        StatusBadgeLarge(statusCode: status, statusMessage: capture.statusMessage)
                    } else {
                        Text("No response")
                            .font(.system(size: 14))
                            .foregroundColor(.ghostTextMuted)
                    }
                }
            }

            // Headers
            if let headers = capture.responseHeadersDictionary, !headers.isEmpty {
                CaptureDetailCard(
                    title: "Headers",
                    copyAction: headersCopyAction(headers),
                    copiedItem: $copiedItem,
                    itemId: "response_headers"
                ) {
                    CaptureHeadersView(headers: headers)
                }
            }

            // Body
            if let body = capture.responseBody, !body.isEmpty {
                CaptureDetailCard(
                    title: "Body (\(formatBytes(body.count)))",
                    copyAction: bodyCopyAction(body),
                    copiedItem: $copiedItem,
                    itemId: "response_body"
                ) {
                    CaptureBodyView(
                        data: body,
                        contentType: capture.contentType
                    )
                }
            } else {
                CaptureDetailCard(title: "Body") {
                    Text("No response body")
                        .font(.system(size: 12))
                        .foregroundColor(.ghostTextMuted)
                }
            }
        }
    }

    private func headersCopyAction(_ headers: [String: String]) -> () -> Void {
        { [self] in copyHeaders(headers) }
    }

    private func bodyCopyAction(_ body: Data) -> () -> Void {
        { [self] in copyBody(body) }
    }

    private func copyHeaders(_ headers: [String: String]) {
        let text = headers.sorted { $0.key < $1.key }
            .map { "\($0.key): \($0.value)" }
            .joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copiedItem = "response_headers"
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if copiedItem == "response_headers" { copiedItem = nil }
        }
    }

    private func copyBody(_ data: Data) {
        if let text = String(data: data, encoding: .utf8) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            copiedItem = "response_body"
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                if copiedItem == "response_body" { copiedItem = nil }
            }
        }
    }

    private func formatBytes(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return String(format: "%.1f KB", Double(bytes) / 1024) }
        return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
    }
}

// MARK: - Preview

#Preview {
    SQLCaptureDetailView(
        capture: Capture(
            method: "POST",
            scheme: "https",
            host: "api.example.com",
            path: "/users/123",
            requestHeaders: "{\"Authorization\": \"Bearer token123\", \"Content-Type\": \"application/json\"}",
            requestBody: Data("{\"name\": \"John\", \"email\": \"john@example.com\"}".utf8),
            requestBodySize: 42,
            statusCode: 200,
            statusMessage: "OK",
            responseHeaders: "{\"Content-Type\": \"application/json\"}",
            responseBody: Data("{\"id\": 123, \"name\": \"John\", \"active\": true}".utf8),
            responseBodySize: 45,
            contentType: "application/json",
            durationMs: 145
        )
    ) {}
    .preferredColorScheme(.dark)
}

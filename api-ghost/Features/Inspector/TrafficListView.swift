import SwiftUI

// MARK: - Traffic List View

struct TrafficListView: View {
    let captures: [Capture]
    @Binding var selectedCapture: Capture?
    @State private var hoveredCaptureId: String?

    var body: some View {
        if captures.isEmpty {
            EmptyTrafficView()
        } else {
            VStack(spacing: 0) {
                TrafficListHeader()

                Divider()
                    .background(Color.ghostBorder)

                ScrollViewReader { _ in
                    List(captures, id: \.uuid, selection: Binding(
                        get: { selectedCapture?.uuid },
                        set: { newValue in
                            selectedCapture = captures.first { $0.uuid == newValue }
                        }
                    )) { capture in
                        TrafficListRow(
                            capture: capture,
                            index: captureIndex(for: capture),
                            isSelected: selectedCapture?.uuid == capture.uuid,
                            isHovered: hoveredCaptureId == capture.uuid
                        )
                        .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                        .listRowBackground(rowBackground(for: capture))
                        .onHover { hovering in
                            hoveredCaptureId = hovering ? capture.uuid : nil
                        }
                        .contextMenu {
                            CaptureContextMenu(capture: capture)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(Color.ghostBase)
                }
            }
        }
    }

    // MARK: - Helper Methods

    private func captureIndex(for capture: Capture) -> Int {
        if let index = captures.firstIndex(where: { $0.uuid == capture.uuid }) {
            return captures.count - index
        }
        return 0
    }

    private func rowBackground(for capture: Capture) -> Color {
        if selectedCapture?.uuid == capture.uuid {
            return Color.ghostAccentMuted
        } else if hoveredCaptureId == capture.uuid {
            return Color.ghostSurfaceRaised
        }
        return Color.clear
    }
}

// MARK: - Traffic List Header

struct TrafficListHeader: View {
    var body: some View {
        HStack(spacing: 0) {
            HeaderCell(title: "#", width: 40, alignment: .trailing)
            HeaderCell(title: "Method", width: 70, alignment: .leading)
            HeaderCell(title: "Domain", width: 150, alignment: .leading)
            HeaderCell(title: "Path", width: nil, alignment: .leading)
            HeaderCell(title: "Status", width: 60, alignment: .center)
            HeaderCell(title: "Size", width: 70, alignment: .trailing)
            HeaderCell(title: "Time", width: 70, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.ghostSurface)
    }
}

struct HeaderCell: View {
    let title: String
    let width: CGFloat?
    let alignment: Alignment

    var body: some View {
        Text(title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(.ghostTextMuted)
            .frame(width: width, alignment: alignment)
            .frame(maxWidth: width == nil ? .infinity : nil, alignment: alignment)
    }
}

// MARK: - Traffic List Row

struct TrafficListRow: View {
    let capture: Capture
    let index: Int
    let isSelected: Bool
    let isHovered: Bool

    var body: some View {
        HStack(spacing: 0) {
            Text("\(index)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.ghostTextMuted)
                .frame(width: 40, alignment: .trailing)

            MethodBadge(method: capture.method)
                .frame(width: 70, alignment: .leading)

            Text(capture.host)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.ghostTextPrimary)
                .lineLimit(1)
                .frame(width: 150, alignment: .leading)

            Text(capture.path)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.ghostTextSecondary)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            StatusBadge(statusCode: capture.statusCode)
                .frame(width: 60, alignment: .center)

            Text(formatSize(capture.responseBodySize))
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.ghostTextMuted)
                .frame(width: 70, alignment: .trailing)

            Text(formatTime(capture.durationMs))
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.ghostTextMuted)
                .frame(width: 70, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }

    private func formatSize(_ bytes: Int) -> String {
        if bytes == 0 { return "-" }
        if bytes < 1024 { return "\(bytes)B" }
        if bytes < 1024 * 1024 { return String(format: "%.1fK", Double(bytes) / 1024) }
        return String(format: "%.1fM", Double(bytes) / (1024 * 1024))
    }

    private func formatTime(_ ms: Int?) -> String {
        guard let ms = ms else { return "-" }
        return "\(ms)ms"
    }
}

// MARK: - Empty Traffic View

struct EmptyTrafficView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "network.slash")
                .font(.system(size: 36))
                .foregroundColor(.ghostTextMuted)

            Text("No Traffic Captured")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.ghostTextSecondary)

            Text("Browse to a website to capture API traffic")
                .font(.system(size: 12))
                .foregroundColor(.ghostTextMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.ghostBase)
    }
}

// MARK: - Method Badge

struct MethodBadge: View {
    let method: String

    var body: some View {
        Text(method)
            .font(.system(size: 10, weight: .bold, design: .monospaced))
            .foregroundColor(methodColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(methodColor.opacity(0.15))
            .cornerRadius(4)
    }

    private var methodColor: Color {
        switch method.uppercased() {
        case "GET": return .ghostMethodGet
        case "POST": return .ghostMethodPost
        case "PUT": return .ghostMethodPut
        case "PATCH": return .ghostMethodPatch
        case "DELETE": return .ghostMethodDelete
        default: return .ghostTextSecondary
        }
    }
}

// MARK: - Status Badge

struct StatusBadge: View {
    let statusCode: Int?

    var body: some View {
        if let code = statusCode {
            Text("\(code)")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(statusColor(for: code))
        } else {
            Text("-")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.ghostTextMuted)
        }
    }

    private func statusColor(for code: Int) -> Color {
        switch code {
        case 200..<300: return .ghostStatus2xx
        case 300..<400: return .ghostStatus3xx
        case 400..<500: return .ghostStatus4xx
        case 500..<600: return .ghostStatus5xx
        default: return .ghostTextSecondary
        }
    }
}

// MARK: - Capture Context Menu

struct CaptureContextMenu: View {
    let capture: Capture

    var body: some View {
        Button("Copy URL") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(capture.fullURL, forType: .string)
        }

        Button("Copy as cURL") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(generateCurlCommand(for: capture), forType: .string)
        }

        Divider()

        Button("Copy Request Headers") {
            if let headers = capture.requestHeaders {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(headers, forType: .string)
            }
        }
        .disabled(capture.requestHeaders == nil)

        Button("Copy Response Body") {
            if let body = capture.responseBody, let text = String(data: body, encoding: .utf8) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            }
        }
        .disabled(capture.responseBody == nil)
    }

    private func generateCurlCommand(for capture: Capture) -> String {
        var command = "curl"

        if capture.method != "GET" {
            command += " -X \(capture.method)"
        }

        command += " '\(capture.fullURL)'"

        if let headersJson = capture.requestHeaders,
           let data = headersJson.data(using: .utf8),
           let headers = try? JSONDecoder().decode([String: String].self, from: data) {
            for (key, value) in headers.sorted(by: { $0.key < $1.key }) {
                if ["host", "content-length", "accept-encoding"].contains(key.lowercased()) {
                    continue
                }
                let escapedValue = value.replacingOccurrences(of: "'", with: "'\\''")
                command += " -H '\(key): \(escapedValue)'"
            }
        }

        if let body = capture.requestBody, let bodyString = String(data: body, encoding: .utf8) {
            let escapedBody = bodyString.replacingOccurrences(of: "'", with: "'\\''")
            command += " --data '\(escapedBody)'"
        }

        return command
    }
}

// MARK: - Preview

#Preview {
    TrafficListView(
        captures: [
            Capture(
                method: "GET",
                scheme: "https",
                host: "api.example.com",
                path: "/users/123",
                statusCode: 200,
                responseBodySize: 1234,
                durationMs: 45
            ),
            Capture(
                method: "POST",
                scheme: "https",
                host: "api.example.com",
                path: "/orders",
                statusCode: 201,
                responseBodySize: 567,
                durationMs: 120
            ),
            Capture(
                method: "DELETE",
                scheme: "https",
                host: "api.example.com",
                path: "/users/456",
                statusCode: 404,
                responseBodySize: 89,
                durationMs: 23
            )
        ],
        selectedCapture: .constant(nil)
    )
    .preferredColorScheme(.dark)
    .frame(width: 800, height: 400)
}

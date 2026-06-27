import SwiftUI
import os

private let logger = Logger(subsystem: "corelift.api-ghost", category: "TrafficDetailView")

// MARK: - Traffic Detail View

struct TrafficDetailView: View {
    let capture: Capture?
    @State private var selectedTab: DetailTab = .request

    var body: some View {
        if let capture = capture {
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    DetailTabButton(tab: .request, selectedTab: $selectedTab)
                    DetailTabButton(tab: .response, selectedTab: $selectedTab)
                    Spacer()

                    TrafficActionButtons(capture: capture)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.ghostSurface)

                Divider()
                    .background(Color.ghostBorder)

                Group {
                    switch selectedTab {
                    case .request:
                        RequestDetailView(capture: capture)
                    case .response:
                        ResponseDetailView(capture: capture)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Color.ghostSurface)
        } else {
            EmptyDetailView()
        }
    }
}

// MARK: - Detail Tab

enum DetailTab: String, CaseIterable {
    case request = "Request"
    case response = "Response"
}

// MARK: - Detail Tab Button

struct DetailTabButton: View {
    let tab: DetailTab
    @Binding var selectedTab: DetailTab

    var isSelected: Bool {
        selectedTab == tab
    }

    var body: some View {
        Button(action: { selectedTab = tab }, label: {
            Text(tab.rawValue)
                .font(.system(size: 12, weight: isSelected ? .semibold : .regular))
                .foregroundColor(isSelected ? .ghostAccent : .ghostTextSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.ghostAccentMuted : Color.clear)
                .cornerRadius(4)
        })
        .buttonStyle(.plain)
    }
}

// MARK: - Empty Detail View

struct EmptyDetailView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 28))
                .foregroundColor(.ghostTextMuted)

            Text("Select a request to inspect")
                .font(.system(size: 13))
                .foregroundColor(.ghostTextSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.ghostSurface)
    }
}

// MARK: - Traffic Action Buttons

struct TrafficActionButtons: View {
    let capture: Capture
    @State private var isReplaying: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            InspectorActionButton(title: "Copy Request", icon: "doc.on.doc") {
                copyRequest()
            }

            InspectorActionButton(title: "Copy Response", icon: "doc.on.doc.fill") {
                copyResponse()
            }

            InspectorActionButton(title: "Copy cURL", icon: "terminal") {
                copyCurl()
            }

            InspectorActionButton(title: "Replay", icon: "arrow.clockwise") {
                replayRequest()
            }
            .disabled(isReplaying)
        }
    }

    private func copyRequest() {
        var requestText = "\(capture.method) \(capture.fullURL)\n\n"

        if let headers = capture.requestHeadersDictionary {
            for (key, value) in headers.sorted(by: { $0.key < $1.key }) {
                requestText += "\(key): \(value)\n"
            }
        }

        if let body = capture.requestBody, let bodyString = String(data: body, encoding: .utf8) {
            requestText += "\n\(bodyString)"
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(requestText, forType: .string)
    }

    private func copyResponse() {
        var responseText = ""

        if let status = capture.statusCode, let message = capture.statusMessage {
            responseText = "HTTP \(status) \(message)\n\n"
        } else if let status = capture.statusCode {
            responseText = "HTTP \(status)\n\n"
        }

        if let headers = capture.responseHeadersDictionary {
            for (key, value) in headers.sorted(by: { $0.key < $1.key }) {
                responseText += "\(key): \(value)\n"
            }
        }

        if let body = capture.responseBody, let bodyString = String(data: body, encoding: .utf8) {
            responseText += "\n\(bodyString)"
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(responseText, forType: .string)
    }

    private func copyCurl() {
        let curl = generateCurlCommand(for: capture)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(curl, forType: .string)
    }

    private func replayRequest() {
        isReplaying = true

        Task {
            defer {
                Task { @MainActor in
                    isReplaying = false
                }
            }

            guard let url = URL(string: capture.fullURL) else { return }

            var request = URLRequest(url: url)
            request.httpMethod = capture.method

            if let headers = capture.requestHeadersDictionary {
                for (key, value) in headers {
                    if ["host", "content-length", "accept-encoding"].contains(key.lowercased()) {
                        continue
                    }
                    request.setValue(value, forHTTPHeaderField: key)
                }
            }

            if let body = capture.requestBody {
                request.httpBody = body
            }

            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                if let httpResponse = response as? HTTPURLResponse {
                    logger.info("Response: \(httpResponse.statusCode)")
                }
            } catch {
                logger.error("Error: \(error.localizedDescription)")
            }
        }
    }

    private func generateCurlCommand(for capture: Capture) -> String {
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

        if let body = capture.requestBody, let bodyString = String(data: body, encoding: .utf8) {
            let escapedBody = bodyString.replacingOccurrences(of: "'", with: "'\\''")
            command += " \\\n  --data '\(escapedBody)'"
        }

        return command
    }
}

// MARK: - Inspector Action Button

struct InspectorActionButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(title)
                    .font(.system(size: 11))
            }
            .foregroundColor(.ghostTextSecondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(Color.ghostSurfaceRaised)
            .cornerRadius(4)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.ghostBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Preview

#Preview {
    TrafficDetailView(
        capture: Capture(
            method: "GET",
            scheme: "https",
            host: "api.example.com",
            path: "/users/123",
            requestHeaders: "{\"Authorization\": \"Bearer token123\", \"Content-Type\": \"application/json\"}",
            statusCode: 200,
            responseHeaders: "{\"Content-Type\": \"application/json\"}",
            responseBody: Data("{\"id\": 123, \"name\": \"John\", \"active\": true}".utf8),
            responseBodySize: 42
        )
    )
    .preferredColorScheme(.dark)
    .frame(width: 800, height: 300)
}

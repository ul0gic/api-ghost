import SwiftUI

/// Always-visible 28px affordance shown when the bottom traffic panel is collapsed (3.4.2).
struct TrafficPanelPeekStrip: View {
    let onExpand: () -> Void

    @State private var appState = AppState.shared
    @State private var trafficCapture = TrafficCapture.shared
    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: onExpand) {
            HStack(spacing: 10) {
                Capsule()
                    .fill(Color.ghostTextMuted)
                    .frame(width: 32, height: 2)

                count(appState.capturedRequestsCount, label: "captured")
                count(appState.filteredRequestsCount, label: "filtered")

                if let preview = lastRequestPreview {
                    Text(preview)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.ghostTextSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }

                Spacer(minLength: 8)

                HStack(spacing: 4) {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 9, weight: .semibold))
                    Text("click to expand")
                        .font(.system(size: 11))
                }
                .foregroundColor(.ghostTextMuted)
            }
            .padding(.horizontal, 12)
            .frame(height: 28)
            .frame(maxWidth: .infinity)
            .background(isHovered ? Color.ghostSurfaceRaised : Color.ghostSurface)
            .overlay(alignment: .top) {
                Rectangle()
                    .fill(Color.ghostBorder)
                    .frame(height: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .help("Show traffic panel")
    }

    private func count(_ value: Int, label: String) -> some View {
        HStack(spacing: 4) {
            Text("\(value)")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .foregroundColor(.ghostAccent)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.ghostTextMuted)
        }
    }

    private var lastRequestPreview: String? {
        guard let capture = trafficCapture.recentCaptures.first else { return nil }
        return "\(capture.method) \(capture.host)\(capture.path)"
    }
}

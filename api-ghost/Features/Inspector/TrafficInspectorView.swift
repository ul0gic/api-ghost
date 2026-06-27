import SwiftUI

// MARK: - Traffic Inspector View

struct TrafficInspectorView: View {
    @State private var trafficCapture = TrafficCapture.shared
    @State private var selectedCapture: Capture?
    @State private var inspectorWidth: CGFloat = Preferences.shared.inspectorPanelWidth
    @State private var isInspectorCollapsed: Bool = Preferences.shared.inspectorPanelCollapsed

    @State private var selectedDomainFilter: String?
    @State private var selectedMethodFilter: String?
    @State private var selectedStatusFilter: String?
    @State private var searchText: String = ""

    private let minimumInspectorWidth: CGFloat = 350
    private let maximumInspectorWidth: CGFloat = 700
    private let minimumListWidth: CGFloat = 300

    var body: some View {
        VStack(spacing: 0) {
            TrafficFilterBar(
                domains: uniqueDomains,
                selectedDomain: $selectedDomainFilter,
                selectedMethod: $selectedMethodFilter,
                selectedStatus: $selectedStatusFilter,
                searchText: $searchText,
                onClearFilters: clearFilters
            )

            Divider()
                .background(Color.ghostBorder)

            GeometryReader { geometry in
                HStack(spacing: 0) {
                    TrafficListView(
                        captures: filteredCaptures,
                        selectedCapture: $selectedCapture
                    )
                    .frame(minWidth: minimumListWidth)
                    .frame(maxWidth: .infinity)

                    if !isInspectorCollapsed {
                        InspectorVerticalResizeHandle(
                            width: $inspectorWidth,
                            minWidth: minimumInspectorWidth,
                            maxWidth: min(maximumInspectorWidth, geometry.size.width - minimumListWidth)
                        ) { newWidth in
                            Preferences.shared.inspectorPanelWidth = newWidth
                        }

                        VStack(spacing: 0) {
                            InspectorHeader(
                                isCollapsed: $isInspectorCollapsed,
                                selectedCapture: selectedCapture
                            )

                            Divider()
                                .background(Color.ghostBorder)

                            TrafficDetailView(capture: selectedCapture)
                        }
                        .frame(width: inspectorWidth)
                        .frame(minWidth: minimumInspectorWidth)
                        .background(Color.ghostSurface)
                    }
                }
            }

            if isInspectorCollapsed {
                InspectorCollapsedBar(
                    isCollapsed: $isInspectorCollapsed,
                    selectedCapture: selectedCapture
                )
            }
        }
        .background(Color.ghostBase)
        .onChange(of: isInspectorCollapsed) { _, newValue in
            Preferences.shared.inspectorPanelCollapsed = newValue
        }
        .onAppear {
            let storedWidth = Preferences.shared.inspectorPanelWidth
            if storedWidth < minimumInspectorWidth || storedWidth > maximumInspectorWidth {
                inspectorWidth = max(minimumInspectorWidth, min(maximumInspectorWidth, storedWidth))
            }
        }
    }

    // MARK: - Computed Properties

    private var uniqueDomains: [String] {
        Array(Set(trafficCapture.recentCaptures.map { $0.host })).sorted()
    }

    private var filteredCaptures: [Capture] {
        var captures = trafficCapture.recentCaptures

        if let domain = selectedDomainFilter {
            captures = captures.filter { $0.host == domain }
        }

        if let method = selectedMethodFilter {
            captures = captures.filter { $0.method == method }
        }

        if let status = selectedStatusFilter {
            captures = captures.filter { capture in
                guard let code = capture.statusCode else { return false }
                switch status {
                case "2xx": return (200..<300).contains(code)
                case "3xx": return (300..<400).contains(code)
                case "4xx": return (400..<500).contains(code)
                case "5xx": return (500..<600).contains(code)
                default: return true
                }
            }
        }

        if !searchText.isEmpty {
            captures = captures.filter { capture in
                capture.path.localizedCaseInsensitiveContains(searchText) ||
                capture.host.localizedCaseInsensitiveContains(searchText) ||
                (capture.requestBody
                    .flatMap { String(data: $0, encoding: .utf8) }?
                    .localizedCaseInsensitiveContains(searchText) ?? false) ||
                (capture.responseBody
                    .flatMap { String(data: $0, encoding: .utf8) }?
                    .localizedCaseInsensitiveContains(searchText) ?? false)
            }
        }

        return captures
    }

    private func clearFilters() {
        selectedDomainFilter = nil
        selectedMethodFilter = nil
        selectedStatusFilter = nil
        searchText = ""
    }
}

// MARK: - Vertical Resize Handle (for horizontal split)

struct InspectorVerticalResizeHandle: View {
    @Binding var width: CGFloat
    let minWidth: CGFloat
    let maxWidth: CGFloat
    var onWidthChanged: ((CGFloat) -> Void)?

    @State private var startWidth: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(Color.ghostBorder)
            .frame(width: 1)
            .overlay(
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 8)
                    .contentShape(Rectangle())
                    .cursor(.resizeLeftRight)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                if startWidth == 0 {
                                    startWidth = width
                                }
                                let newWidth = startWidth - value.translation.width
                                width = max(minWidth, min(maxWidth, newWidth))
                            }
                            .onEnded { _ in
                                startWidth = 0
                                onWidthChanged?(width)
                            }
                    )
            )
    }
}

// MARK: - Inspector Header (shown when expanded)

struct InspectorHeader: View {
    @Binding var isCollapsed: Bool
    let selectedCapture: Capture?

    var body: some View {
        HStack {
            Text("Inspector")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.ghostTextPrimary)

            Spacer()

            if let capture = selectedCapture {
                Text("\(capture.method) \(capture.path)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.ghostTextMuted)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()

            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isCollapsed = true
                }
            }, label: {
                Image(systemName: "sidebar.right")
                    .font(.system(size: 12))
                    .foregroundColor(.ghostTextSecondary)
            })
            .buttonStyle(.plain)
            .help("Hide Inspector")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.ghostSurface)
    }
}

// MARK: - Inspector Collapsed Bar (shown when collapsed)

struct InspectorCollapsedBar: View {
    @Binding var isCollapsed: Bool
    let selectedCapture: Capture?

    var body: some View {
        HStack {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isCollapsed = false
                }
            }, label: {
                HStack(spacing: 6) {
                    Image(systemName: "sidebar.right")
                        .font(.system(size: 10, weight: .semibold))

                    Text("Show Inspector")
                        .font(.system(size: 11))
                }
                .foregroundColor(.ghostTextSecondary)
            })
            .buttonStyle(.plain)

            Spacer()

            if let capture = selectedCapture {
                Text("\(capture.method) \(capture.path)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.ghostTextMuted)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.ghostSurface)
    }
}

// MARK: - View Extension for Cursor

extension View {
    func cursor(_ cursor: NSCursor) -> some View {
        self.onHover { hovering in
            if hovering {
                cursor.push()
            } else {
                NSCursor.pop()
            }
        }
    }
}

// MARK: - Preview

#Preview {
    TrafficInspectorView()
        .preferredColorScheme(.dark)
        .frame(width: 1000, height: 600)
}

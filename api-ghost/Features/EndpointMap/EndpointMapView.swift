//
//  EndpointMapView.swift
//  api-ghost
//
//  Endpoint Map view displaying captured API endpoints in a hierarchical tree.
//  Shows domains, path segments, methods, call counts, and findings.
//

import SwiftUI

// MARK: - Endpoint Map View

struct EndpointMapView: View {
    @State private var treeNodes: [EndpointTreeNode] = []
    @State private var isLoading: Bool = true
    @State private var selectedNode: EndpointTreeNode?
    @State private var showExportSheet: Bool = false

    // Summary stats
    @State private var domainCount: Int = 0
    @State private var endpointCount: Int = 0
    @State private var requestCount: Int = 0
    @State private var findingsCount: Int = 0

    var body: some View {
        VStack(spacing: 0) {
            // Header with Export button
            headerBar

            Divider()
                .background(Color.ghostBorder)

            if isLoading {
                loadingView
            } else if treeNodes.isEmpty {
                emptyStateView
            } else {
                // Tree content
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(treeNodes) { node in
                            EndpointTreeRow(
                                node: node,
                                depth: 0,
                                selectedNode: $selectedNode
                            )
                        }
                    }
                    .padding(.vertical, 8)
                }

                Divider()
                    .background(Color.ghostBorder)

                // Summary footer
                summaryFooter
            }
        }
        .background(Color.ghostBase)
        .onAppear {
            loadEndpoints()
        }
        .sheet(isPresented: $showExportSheet) {
            ExportDialogView()
        }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack {
            Text("Endpoint Map")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.ghostTextPrimary)

            Spacer()

            if findingsCount > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.ghostWarning)
                    Text("\(findingsCount) findings")
                        .foregroundColor(.ghostWarning)
                }
                .font(.system(size: 11))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.ghostWarning.opacity(0.15))
                .cornerRadius(4)
            }

            Button(action: { loadEndpoints() }, label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12))
                    .foregroundColor(.ghostTextSecondary)
            })
            .buttonStyle(.plain)
            .help("Refresh endpoint map")

            Button(action: { showExportSheet = true }, label: {
                HStack(spacing: 4) {
                    Image(systemName: "square.and.arrow.up")
                    Text("Export")
                }
                .font(.system(size: 12))
                .foregroundColor(.ghostAccent)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(Color.ghostAccentMuted)
                .cornerRadius(4)
            })
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.ghostSurface)
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .ghostAccent))
            Text("Loading endpoints...")
                .font(.system(size: 13))
                .foregroundColor(.ghostTextSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty State View

    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 40))
                .foregroundColor(.ghostTextMuted)
            Text("Endpoint Map Coming Soon")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(.ghostTextSecondary)
            Text("API visualization with charts and relationship graphs")
                .font(.system(size: 13))
                .foregroundColor(.ghostTextMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Summary Footer

    private var summaryFooter: some View {
        HStack(spacing: 24) {
            summaryItem(label: "Domains", value: domainCount, color: .ghostAccent)
            summaryItem(label: "Endpoints", value: endpointCount, color: .ghostAccent)
            summaryItem(label: "Requests", value: requestCount, color: .ghostAccent)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.ghostSurface)
    }

    private func summaryItem(label: String, value: Int, color: Color) -> some View {
        HStack(spacing: 6) {
            Text("\(value)")
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundColor(color)
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.ghostTextMuted)
        }
    }

    // MARK: - Data Loading

    private func loadEndpoints() {
        // TODO: Rewrite with SQL aggregation for performance
        // Current implementation loads all captures into memory which hangs with large datasets
        // For now, show empty state - will rebuild with charts/graphs visualization
        isLoading = false
        treeNodes = []
        domainCount = 0
        endpointCount = 0
        requestCount = 0
        findingsCount = 0
    }
}

// MARK: - Endpoint Tree Row

struct EndpointTreeRow: View {
    @ObservedObject var node: EndpointTreeNode
    let depth: Int
    @Binding var selectedNode: EndpointTreeNode?

    @State private var isHovered: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Row content
            HStack(spacing: 0) {
                // Indentation
                ForEach(0..<depth, id: \.self) { _ in
                    Rectangle()
                        .fill(Color.clear)
                        .frame(width: 16)
                }

                // Expand/collapse button for nodes with children
                if node.hasChildren {
                    Button(action: { node.isExpanded.toggle() }, label: {
                        Image(systemName: node.isExpanded ? "chevron.down" : "chevron.right")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.ghostTextMuted)
                            .frame(width: 16, height: 16)
                    })
                    .buttonStyle(.plain)
                } else {
                    Rectangle()
                        .fill(Color.clear)
                        .frame(width: 16)
                }

                // Node icon
                nodeIcon
                    .frame(width: 20)

                // Node content based on type
                switch node.nodeType {
                case .domain:
                    domainContent
                case .pathSegment:
                    pathSegmentContent
                case .endpoint:
                    endpointContent
                }

                Spacer()

                // Findings indicator
                if node.findingsCount > 0 {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.ghostWarning)
                        .padding(.trailing, 4)
                }

                // Call count badge
                if node.totalCallCount > 0 {
                    Text("\(node.totalCallCount)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.ghostTextMuted)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.ghostSurfaceRaised)
                        .cornerRadius(4)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(backgroundColor)
            .onHover { hovering in
                isHovered = hovering
            }
            .onTapGesture {
                if node.hasChildren {
                    node.isExpanded.toggle()
                } else {
                    selectedNode = node
                }
            }

            // Expanded children
            if node.isExpanded {
                ForEach(node.children) { child in
                    EndpointTreeRow(
                        node: child,
                        depth: depth + 1,
                        selectedNode: $selectedNode
                    )
                }
            }
        }
    }

    // MARK: - Node Icon

    private var nodeIcon: some View {
        Group {
            switch node.nodeType {
            case .domain:
                Image(systemName: "globe")
                    .font(.system(size: 12))
                    .foregroundColor(.ghostAccent)
            case .pathSegment:
                Image(systemName: "folder")
                    .font(.system(size: 12))
                    .foregroundColor(.ghostTextMuted)
            case .endpoint:
                methodBadge
            }
        }
    }

    // MARK: - Method Badge

    private var methodBadge: some View {
        Text(node.method ?? "")
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundColor(methodColor)
    }

    private var methodColor: Color {
        guard let method = node.method?.uppercased() else { return .ghostTextMuted }
        switch method {
        case "GET": return .ghostMethodGet
        case "POST": return .ghostMethodPost
        case "PUT": return .ghostMethodPut
        case "PATCH": return .ghostMethodPatch
        case "DELETE": return .ghostMethodDelete
        default: return .ghostTextMuted
        }
    }

    // MARK: - Content Views

    private var domainContent: some View {
        Text(node.name)
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(.ghostTextPrimary)
    }

    private var pathSegmentContent: some View {
        Text(node.name)
            .font(.system(size: 12, design: .monospaced))
            .foregroundColor(.ghostTextSecondary)
    }

    private var endpointContent: some View {
        HStack(spacing: 8) {
            Text(node.pathPattern ?? node.name)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.ghostTextPrimary)
                .lineLimit(1)

            if let status = node.typicalStatus {
                Text("\(status)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(statusColor(for: status))
            }
        }
    }

    // MARK: - Helpers

    private var backgroundColor: Color {
        if selectedNode?.id == node.id {
            return .ghostAccentMuted
        } else if isHovered {
            return .ghostSurfaceRaised
        }
        return .clear
    }

    private func statusColor(for code: Int) -> Color {
        switch code {
        case 200..<300: return .ghostStatus2xx
        case 300..<400: return .ghostStatus3xx
        case 400..<500: return .ghostStatus4xx
        case 500..<600: return .ghostStatus5xx
        default: return .ghostTextMuted
        }
    }
}

// MARK: - Preview

#Preview {
    EndpointMapView()
        .preferredColorScheme(.dark)
        .frame(width: 600, height: 500)
}

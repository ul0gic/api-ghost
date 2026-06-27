//
//  MapTreeRows.swift
//  APIGhost
//
//  Tree row views for the API Map: domain rows, path node rows, and endpoint rows.
//

import SwiftUI

// MARK: - Map Domain Row

struct MapDomainRow: View {
    @ObservedObject var domain: APIDomain
    let searchText: String
    @Binding var selectedEndpoint: APIEndpoint?

    @State private var isHovered: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Domain header
            HStack(spacing: 8) {
                // Expand/collapse
                Button(action: { domain.isExpanded.toggle() }, label: {
                    Image(systemName: domain.isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.ghostTextMuted)
                        .frame(width: 16, height: 16)
                })
                .buttonStyle(.plain)

                // Domain icon
                Image(systemName: "globe")
                    .font(.system(size: 12))
                    .foregroundColor(.ghostAccent)

                // Host name
                Text(domain.host)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.ghostTextPrimary)

                Spacer()

                // Methods used
                HStack(spacing: 4) {
                    ForEach(Array(domain.methods).sorted(), id: \.self) { method in
                        MapMethodBadge(method: method, size: .tiny)
                    }
                }

                // Endpoint count
                Text("\(domain.uniqueEndpoints) endpoints")
                    .font(.system(size: 11))
                    .foregroundColor(.ghostTextMuted)

                // Request count
                Text("\(domain.totalRequests)")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .foregroundColor(.ghostTextSecondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.ghostSurfaceRaised)
                    .cornerRadius(4)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isHovered ? Color.ghostSurfaceRaised : Color.clear)
            .onHover { hovering in
                isHovered = hovering
            }
            .onTapGesture {
                domain.isExpanded.toggle()
            }

            // Children
            if domain.isExpanded {
                ForEach(domain.rootNodes) { node in
                    PathNodeRow(
                        node: node,
                        depth: 1,
                        searchText: searchText,
                        selectedEndpoint: $selectedEndpoint
                    )
                }
            }
        }
    }
}

// MARK: - Path Node Row

struct PathNodeRow: View {
    @ObservedObject var node: PathNode
    let depth: Int
    let searchText: String
    @Binding var selectedEndpoint: APIEndpoint?

    @State private var isHovered: Bool = false

    private let indentWidth: CGFloat = 20

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Node header (only show if has children or is a parameter)
            if node.hasChildren || node.isParameter {
                nodeHeader
            }

            // Expanded content
            if node.isExpanded || (!node.hasChildren && node.endpoints.isEmpty) {
                nodeChildren
            }
        }
    }

    private var nodeHeader: some View {
        HStack(spacing: 6) {
            // Indentation
            ForEach(0..<depth, id: \.self) { _ in
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: indentWidth)
            }

            // Expand/collapse (if has nested content)
            if !node.children.isEmpty || !node.endpoints.isEmpty {
                Button(action: { node.isExpanded.toggle() }, label: {
                    Image(systemName: node.isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.ghostTextMuted)
                        .frame(width: 14, height: 14)
                })
                .buttonStyle(.plain)
            } else {
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 14)
            }

            // Segment display
            if node.isParameter {
                ParameterBadge(type: node.parameterType ?? .unknown)
            } else {
                Text("/\(node.segment)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.ghostTextSecondary)
            }

            Spacer()

            // Total count for this subtree
            if node.totalHitCount > 0 {
                Text("\(node.totalHitCount)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.ghostTextMuted)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.ghostSurfaceRaised)
                    .cornerRadius(3)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(isHovered ? Color.ghostSurfaceRaised.opacity(0.5) : Color.clear)
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture {
            if !node.children.isEmpty || !node.endpoints.isEmpty {
                node.isExpanded.toggle()
            }
        }
    }

    private var nodeChildren: some View {
        Group {
            // Child nodes
            ForEach(node.children) { child in
                PathNodeRow(
                    node: child,
                    depth: depth + 1,
                    searchText: searchText,
                    selectedEndpoint: $selectedEndpoint
                )
            }

            // Endpoints at this level
            ForEach(node.endpoints) { endpoint in
                EndpointRow(
                    endpoint: endpoint,
                    depth: depth + 1,
                    isSelected: selectedEndpoint?.id == endpoint.id
                ) {
                    selectedEndpoint = endpoint
                }
            }
        }
    }
}

// MARK: - Endpoint Row

struct EndpointRow: View {
    let endpoint: APIEndpoint
    let depth: Int
    let isSelected: Bool
    let onSelect: () -> Void

    @State private var isHovered: Bool = false

    private let indentWidth: CGFloat = 20

    var body: some View {
        HStack(spacing: 6) {
            // Indentation
            ForEach(0..<depth, id: \.self) { _ in
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: indentWidth)
            }

            // Leaf indicator
            Image(systemName: "arrow.right")
                .font(.system(size: 8))
                .foregroundColor(.ghostTextMuted)
                .frame(width: 14)

            // Method badge
            MapMethodBadge(method: endpoint.method, size: .normal)

            // Path (just the last segment since parent shows context)
            Text(pathSuffix)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.ghostTextPrimary)
                .lineLimit(1)

            Spacer()

            // Status codes
            HStack(spacing: 3) {
                ForEach(Array(endpoint.statusCodes).sorted().prefix(3), id: \.self) { code in
                    StatusCodeBadge(code: code)
                }
                if endpoint.statusCodes.count > 3 {
                    Text("+\(endpoint.statusCodes.count - 3)")
                        .font(.system(size: 9))
                        .foregroundColor(.ghostTextMuted)
                }
            }

            // Hit count
            Text("\(endpoint.hitCount)")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(.ghostTextSecondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.ghostSurfaceRaised)
                .cornerRadius(4)

            // Request/Response indicators
            HStack(spacing: 4) {
                if endpoint.hasRequestBody {
                    Image(systemName: "arrow.up.square.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.ghostTextMuted)
                        .help("Has request body")
                }
                if endpoint.hasResponseBody {
                    Image(systemName: "arrow.down.square.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.ghostTextMuted)
                        .help("Has response body")
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(backgroundColor)
        .onHover { hovering in
            isHovered = hovering
        }
        .onTapGesture {
            onSelect()
        }
    }

    private var backgroundColor: Color {
        if isSelected {
            return Color.ghostAccentMuted
        } else if isHovered {
            return Color.ghostSurfaceRaised
        }
        return Color.clear
    }

    private var pathSuffix: String {
        let segments = endpoint.normalizedPath.split(separator: "/")
        if let last = segments.last {
            return String(last)
        }
        return endpoint.normalizedPath
    }
}

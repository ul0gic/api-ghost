import SwiftUI

// MARK: - Target Domain Row

struct TargetDomainRow: View {
    @ObservedObject var domain: APIDomain
    let searchText: String
    @Binding var selection: EndpointDetail?

    @State private var isHovered: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            domainHeader

            if domain.isExpanded {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(domain.rootNodes) { node in
                        PathNodeRow(
                            node: node,
                            parentPath: "",
                            host: domain.host,
                            searchText: searchText,
                            selection: $selection
                        )
                    }
                }
                .padding(.leading, 18)
                .overlay(alignment: .leading) {
                    Rectangle().fill(Color.ghostBorder).frame(width: 1)
                }
                .padding(.top, 2)
            }
        }
        .padding(.bottom, 8)
    }

    private var domainHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: domain.isExpanded ? "chevron.down" : "chevron.right")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.ghostTextMuted)
                .frame(width: 12)

            Text(domain.host)
                .font(.system(size: 13, weight: .medium, design: .monospaced))
                .foregroundColor(.ghostTextPrimary)

            Spacer()

            Text("\(domain.totalRequests) req")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.ghostTextMuted)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color.ghostSurfaceRaised)
                .cornerRadius(4)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isHovered ? Color.ghostSurfaceRaised : Color.ghostSurface)
        .overlay(
            RoundedRectangle(cornerRadius: 7).stroke(Color.ghostBorder, lineWidth: 1)
        )
        .cornerRadius(7)
        .onHover { isHovered = $0 }
        .onTapGesture { domain.isExpanded.toggle() }
    }
}

// MARK: - Path Node Row

struct PathNodeRow: View {
    @ObservedObject var node: PathNode
    let parentPath: String
    let host: String
    let searchText: String
    @Binding var selection: EndpointDetail?

    private var fullPath: String { "\(parentPath)/\(node.segment)" }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            if node.isParameter {
                inlineEndpoints(parentPath: parentPath)
                childNodes
            } else {
                groupHeader
                if node.isExpanded {
                    VStack(alignment: .leading, spacing: 1) {
                        inlineEndpoints(parentPath: fullPath)
                        childNodes
                    }
                    .padding(.leading, 16)
                }
            }
        }
    }

    private var groupHeader: some View {
        HStack(spacing: 6) {
            Image(systemName: node.isExpanded ? "chevron.down" : "chevron.right")
                .font(.system(size: 9, weight: .medium))
                .foregroundColor(.ghostTextMuted)
                .frame(width: 12)

            Text("/\(node.segment)")
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.ghostTextSecondary)

            Spacer()

            if node.totalHitCount > 0 {
                Text("\(node.totalHitCount)×")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.ghostTextMuted)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .contentShape(Rectangle())
        .onTapGesture { node.isExpanded.toggle() }
    }

    @ViewBuilder
    private func inlineEndpoints(parentPath: String) -> some View {
        ForEach(node.endpoints) { endpoint in
            if endpoint.isGraphQL {
                GraphQLBlock(
                    endpoint: endpoint,
                    displayPath: relativePath(endpoint.normalizedPath, from: parentPath),
                    host: host,
                    selection: $selection
                )
            } else {
                EndpointRow(
                    endpoint: endpoint,
                    displayPath: relativePath(endpoint.normalizedPath, from: parentPath),
                    host: host,
                    selection: $selection
                )
            }
        }
    }

    @ViewBuilder private var childNodes: some View {
        ForEach(node.children) { child in
            PathNodeRow(
                node: child,
                parentPath: node.isParameter ? parentPath : fullPath,
                host: host,
                searchText: searchText,
                selection: $selection
            )
        }
    }

    private func relativePath(_ path: String, from prefix: String) -> String {
        guard path.hasPrefix(prefix), path.count > prefix.count else { return "/" }
        return String(path.dropFirst(prefix.count))
    }
}

// MARK: - Endpoint Row

struct EndpointRow: View {
    let endpoint: APIEndpoint
    let displayPath: String
    let host: String
    @Binding var selection: EndpointDetail?

    @State private var isHovered: Bool = false

    private var isSelected: Bool { selection?.id == endpoint.id }

    var body: some View {
        HStack(spacing: 8) {
            OpMethodBadge(method: endpoint.method)
            ParameterizedPathText(path: displayPath)
            Spacer()
            HStack(spacing: 6) {
                Text("\(endpoint.hitCount)×")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.ghostTextMuted)
                StatusRollupChips(counts: endpoint.sortedStatusCounts)
            }
        }
        .padding(.horizontal, 8)
        .frame(height: 36)
        .background(backgroundColor)
        .overlay(alignment: .leading) {
            if isSelected {
                Rectangle().fill(Color.ghostAccent).frame(width: 2)
            }
        }
        .cornerRadius(5)
        .contentShape(Rectangle())
        .onHover { isHovered = $0 }
        .onTapGesture { selection = EndpointDetail.from(endpoint: endpoint, host: host) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(endpoint.method) \(displayPath), \(endpoint.hitCount) requests")
        .accessibilityAddTraits(.isButton)
    }

    private var backgroundColor: Color {
        if isSelected { return Color.ghostAccentMuted }
        if isHovered { return Color.ghostSurfaceRaised }
        return Color.clear
    }
}

// MARK: - GraphQL Block

struct GraphQLBlock: View {
    let endpoint: APIEndpoint
    let displayPath: String
    let host: String
    @Binding var selection: EndpointDetail?

    @State private var isExpanded: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow

            if isExpanded {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(endpoint.graphqlOperations) { operation in
                        operationRow(operation)
                    }
                }
                .padding(.vertical, 4)
                .background(Color.ghostSurface)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 7).stroke(Color.ghostAccent.opacity(0.15), lineWidth: 1)
        )
        .cornerRadius(7)
        .padding(.vertical, 4)
    }

    private var headerRow: some View {
        HStack(spacing: 8) {
            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(.ghostAccent)
                .frame(width: 12)
            OpMethodBadge(method: endpoint.method)
            Text(displayPath)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.ghostTextSecondary)
            Text("GraphQL")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(.ghostAccent)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.ghostAccentMuted)
                .overlay(
                    RoundedRectangle(cornerRadius: 3).stroke(Color.ghostAccent.opacity(0.2), lineWidth: 1)
                )
                .cornerRadius(3)
            Spacer()
            Text("\(endpoint.hitCount)×")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.ghostTextMuted)
            StatusRollupChips(counts: endpoint.sortedStatusCounts)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(Color.ghostAccent.opacity(0.04))
        .contentShape(Rectangle())
        .onTapGesture { isExpanded.toggle() }
    }

    private func operationRow(_ operation: GraphQLOperation) -> some View {
        let isSelected = selection?.id == operation.id
        return HStack(spacing: 8) {
            GraphQLOpTypeBadge(type: operation.type)
            Text(operation.name)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.ghostTextPrimary)
                .lineLimit(1)
            Spacer()
            Text(operation.hitCount > 0 ? "\(operation.hitCount)×" : "—")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.ghostTextMuted)
            StatusRollupChips(counts: operation.sortedStatusCounts)
        }
        .padding(.horizontal, 16)
        .frame(height: 32)
        .background(isSelected ? Color.ghostAccentMuted : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { selection = EndpointDetail.from(operation: operation, host: host) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(operation.type.label) \(operation.name), \(operation.hitCount) requests")
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Third-Party Row

struct ThirdPartyRow: View {
    @ObservedObject var domain: APIDomain

    @State private var isHovered: Bool = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "chevron.right")
                .font(.system(size: 10))
                .foregroundColor(.ghostTextMuted)
                .frame(width: 12)

            Text(domain.host)
                .font(.system(size: 12, design: .monospaced))
                .foregroundColor(.ghostTextSecondary)

            Spacer()

            if let category = domain.category {
                Text(category)
                    .font(.system(size: 11))
                    .foregroundColor(.ghostTextMuted)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Color.ghostSurfaceRaised)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4).stroke(Color.ghostBorder, lineWidth: 1)
                    )
                    .cornerRadius(4)
            }

            Text("\(domain.totalRequests)")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.ghostTextMuted)
                .frame(minWidth: 24, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isHovered ? Color.ghostSurfaceRaised : Color.clear)
        .onHover { isHovered = $0 }
    }
}

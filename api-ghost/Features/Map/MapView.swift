//
//  MapView.swift
//  APIGhost
//
//  Main API Map view displaying captured endpoints in a hierarchical tree.
//  Shows normalized paths with parameter detection, methods, status codes, and hit counts.
//

import SwiftUI

// MARK: - Map View

struct MapView: View {
    @State private var viewModel = MapViewModel()
    @State private var searchText: String = ""
    @State private var selectedEndpoint: APIEndpoint?
    @State private var showingEndpointDetail: Bool = false

    var body: some View {
        VStack(spacing: 0) {
            headerBar
            Divider().background(Color.ghostBorder)

            if viewModel.isLoading {
                loadingView
            } else if viewModel.domains.isEmpty {
                emptyStateView
            } else {
                HSplitView {
                    treeContent.frame(minWidth: 400)
                    if let endpoint = selectedEndpoint {
                        EndpointDetailPanel(endpoint: endpoint) {
                            selectedEndpoint = nil
                        }
                        .frame(minWidth: 300, idealWidth: 350, maxWidth: 450)
                    }
                }
            }

            if !viewModel.domains.isEmpty {
                Divider().background(Color.ghostBorder)
                statsFooter
            }
        }
        .background(Color.ghostBase)
        .onAppear { viewModel.loadMap() }
    }

    // MARK: - Header Bar

    private var headerBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "map.fill")
                    .font(.system(size: 14))
                    .foregroundColor(.ghostAccent)
                Text("API Map")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.ghostTextPrimary)
            }

            if !viewModel.isLoading && !viewModel.domains.isEmpty {
                HStack(spacing: 16) {
                    quickStat(label: "Domains", value: viewModel.statistics.domainCount)
                    quickStat(label: "Endpoints", value: viewModel.statistics.endpointCount)
                    quickStat(label: "Requests", value: viewModel.statistics.totalRequests)
                }
                .padding(.leading, 12)
            }

            Spacer()

            searchField
            refreshButton
            expandCollapseMenu
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.ghostSurface)
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundColor(.ghostTextMuted)
            TextField("Filter endpoints...", text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundColor(.ghostTextPrimary)
                .frame(width: 150)
            if !searchText.isEmpty {
                Button(action: { searchText = "" }, label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.ghostTextMuted)
                })
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Color.ghostInput)
        .cornerRadius(6)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(Color.ghostBorder, lineWidth: 1)
        )
    }

    private var refreshButton: some View {
        Button(action: { viewModel.loadMap() }, label: {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 12))
                .foregroundColor(.ghostTextSecondary)
        })
        .buttonStyle(.plain)
        .help("Refresh API Map")
    }

    private var expandCollapseMenu: some View {
        Menu {
            Button("Expand All") { viewModel.expandAll() }
            Button("Collapse All") { viewModel.collapseAll() }
        } label: {
            Image(systemName: "sidebar.squares.left")
                .font(.system(size: 12))
                .foregroundColor(.ghostTextSecondary)
        }
        .menuStyle(.borderlessButton)
        .frame(width: 24)
        .help("Expand/Collapse")
    }

    private func quickStat(label: String, value: Int) -> some View {
        HStack(spacing: 4) {
            Text("\(value)")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                .foregroundColor(.ghostAccent)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(.ghostTextMuted)
        }
    }

    // MARK: - Tree Content

    private var treeContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(filteredDomains) { domain in
                    MapDomainRow(
                        domain: domain,
                        searchText: searchText,
                        selectedEndpoint: $selectedEndpoint
                    )
                }
            }
            .padding(.vertical, 8)
        }
        .background(Color.ghostBase)
    }

    private var filteredDomains: [APIDomain] {
        if searchText.isEmpty { return viewModel.domains }
        let lowercasedSearch = searchText.lowercased()
        return viewModel.domains.filter { domain in
            domain.host.lowercased().contains(lowercasedSearch) ||
            containsMatchingEndpoint(in: domain, search: lowercasedSearch)
        }
    }

    private func containsMatchingEndpoint(in domain: APIDomain, search: String) -> Bool {
        func checkNode(_ node: PathNode) -> Bool {
            if node.segment.lowercased().contains(search) { return true }
            for endpoint in node.endpoints
                where endpoint.normalizedPath.lowercased().contains(search) ||
                      endpoint.method.lowercased().contains(search) {
                return true
            }
            return node.children.contains { checkNode($0) }
        }
        return domain.rootNodes.contains { checkNode($0) }
    }

    // MARK: - Loading View

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .ghostAccent))
                .scaleEffect(1.2)
            Text("Building API Map...")
                .font(.system(size: 14))
                .foregroundColor(.ghostTextSecondary)
            Text("Analyzing captured endpoints")
                .font(.system(size: 12))
                .foregroundColor(.ghostTextMuted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Empty State View

    private var emptyStateView: some View {
        VStack(spacing: 16) {
            Image(systemName: "map")
                .font(.system(size: 48))
                .foregroundColor(.ghostTextMuted)
            Text("No Endpoints Captured")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.ghostTextSecondary)
            Text("Browse some websites to capture API traffic.\nThe map will show all discovered endpoints.")
                .font(.system(size: 13))
                .foregroundColor(.ghostTextMuted)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
            Button(action: {
                AppState.shared.selectedTab = .browser
            }, label: {
                HStack(spacing: 6) {
                    Image(systemName: "globe")
                    Text("Open Browser")
                }
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.ghostAccent)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.ghostAccentMuted)
                .cornerRadius(6)
            })
            .buttonStyle(.plain)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Stats Footer

    private var statsFooter: some View {
        HStack(spacing: 24) {
            methodBreakdown
            Spacer()
            statusCodeSummary
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.ghostSurface)
    }

    private var methodBreakdown: some View {
        HStack(spacing: 12) {
            ForEach(["GET", "POST", "PUT", "PATCH", "DELETE"], id: \.self) { method in
                if let count = viewModel.statistics.methodBreakdown[method], count > 0 {
                    HStack(spacing: 4) {
                        MapMethodBadge(method: method, size: .small)
                        Text("\(count)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.ghostTextSecondary)
                    }
                }
            }
        }
    }

    private var statusCodeSummary: some View {
        HStack(spacing: 12) {
            let statusGroups = groupStatusCodes(viewModel.statistics.statusCodeBreakdown)
            ForEach(["2xx", "3xx", "4xx", "5xx"], id: \.self) { group in
                if let count = statusGroups[group], count > 0 {
                    HStack(spacing: 4) {
                        Text(group)
                            .font(.system(size: 10, weight: .medium, design: .monospaced))
                            .foregroundColor(statusGroupColor(group))
                        Text("\(count)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(.ghostTextSecondary)
                    }
                }
            }
        }
    }

    private func groupStatusCodes(_ breakdown: [Int: Int]) -> [String: Int] {
        var groups: [String: Int] = [:]
        for (code, count) in breakdown {
            let group: String
            switch code {
            case 200..<300: group = "2xx"
            case 300..<400: group = "3xx"
            case 400..<500: group = "4xx"
            case 500..<600: group = "5xx"
            default: continue
            }
            groups[group, default: 0] += count
        }
        return groups
    }

    private func statusGroupColor(_ group: String) -> Color {
        switch group {
        case "2xx": return .ghostStatus2xx
        case "3xx": return .ghostStatus3xx
        case "4xx": return .ghostStatus4xx
        case "5xx": return .ghostStatus5xx
        default: return .ghostTextMuted
        }
    }
}

// MARK: - Preview

#Preview("Map View") {
    MapView()
        .preferredColorScheme(.dark)
        .frame(width: 900, height: 600)
}

#Preview("Map View - Empty") {
    MapView()
        .preferredColorScheme(.dark)
        .frame(width: 600, height: 400)
}

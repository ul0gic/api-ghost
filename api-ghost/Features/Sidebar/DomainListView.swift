import SwiftUI
import Combine
import os

private let logger = Logger(subsystem: "corelift.api-ghost", category: "DomainListView")

struct DomainListView: View {
    @State private var expandedDomains: Set<String> = []
    @State private var domains: [DomainItem] = []
    @State private var selectedDomain: String?

    private let captureStore = CaptureStore.shared
    private let trafficCapture = TrafficCapture.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if domains.isEmpty {
                Text("No domains captured")
                    .font(.system(size: 12))
                    .foregroundColor(.ghostTextMuted)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if selectedDomain != nil {
                            Button(action: clearSelection) {
                                HStack(spacing: 6) {
                                    Image(systemName: "xmark.circle.fill")
                                        .font(.system(size: 10))
                                        .foregroundColor(.ghostTextMuted)

                                    Text("Clear filter")
                                        .font(.system(size: 11))
                                        .foregroundColor(.ghostTextSecondary)

                                    Spacer()
                                }
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                            }
                            .buttonStyle(.plain)

                            Divider()
                                .background(Color.ghostBorder)
                                .padding(.vertical, 4)
                        }

                        ForEach(domains) { domain in
                            DomainRow(
                                domain: domain,
                                isExpanded: expandedDomains.contains(domain.name),
                                isSelected: selectedDomain == domain.name,
                                onToggle: {
                                    if expandedDomains.contains(domain.name) {
                                        expandedDomains.remove(domain.name)
                                    } else {
                                        expandedDomains.insert(domain.name)
                                    }
                                },
                                onSelect: {
                                    selectDomain(domain.name)
                                }
                            )
                        }
                    }
                }
                .frame(maxHeight: 200)
            }
        }
        .onAppear {
            loadDomains()
        }
        .onReceive(NotificationCenter.default.publisher(for: .clearTrafficList)) { _ in
            clearSelection()
        }
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            loadDomains()
        }
    }

    // MARK: - Actions

    private func loadDomains() {
        Task {
            do {
                let domainCounts = try captureStore.fetchDomains()
                let endpoints = try captureStore.fetchEndpointsByDomain()

                await MainActor.run {
                    domains = domainCounts.map { hostCount in
                        let host = hostCount.host
                        let count = hostCount.count

                        let domainEndpoints = endpoints[host] ?? []
                        let paths = domainEndpoints.map { endpoint in
                            PathItem(
                                path: endpoint.pathPattern,
                                method: endpoint.method,
                                count: endpoint.callCount
                            )
                        }

                        return DomainItem(
                            name: host,
                            requestCount: count,
                            paths: paths
                        )
                    }
                }
            } catch {
                logger.error("Failed to load domains: \(error)")
            }
        }
    }

    private func selectDomain(_ domain: String) {
        withAnimation(.easeInOut(duration: 0.2)) {
            if selectedDomain == domain {
                selectedDomain = nil
                AppState.shared.selectedDomain = nil
            } else {
                selectedDomain = domain
                AppState.shared.selectedDomain = domain
            }
        }
    }

    private func clearSelection() {
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedDomain = nil
            AppState.shared.selectedDomain = nil
        }
    }
}

// MARK: - Domain Item Model

struct DomainItem: Identifiable {
    let id = UUID()
    let name: String
    let requestCount: Int
    let paths: [PathItem]
}

// MARK: - Path Item Model

struct PathItem: Identifiable {
    let id = UUID()
    let path: String
    let method: String
    let count: Int
}

// MARK: - Domain Row

struct DomainRow: View {
    let domain: DomainItem
    let isExpanded: Bool
    let isSelected: Bool
    let onToggle: () -> Void
    let onSelect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                Button(action: onToggle) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10))
                        .foregroundColor(.ghostTextMuted)
                        .frame(width: 20, height: 24)
                }
                .buttonStyle(.plain)

                Button(action: onSelect) {
                    HStack(spacing: 6) {
                        Text(domain.name)
                            .font(.system(size: 12))
                            .foregroundColor(isSelected ? .ghostAccent : .ghostTextPrimary)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Spacer()

                        Text("\(domain.requestCount)")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(isSelected ? .ghostAccent : .ghostTextSecondary)
                    }
                    .padding(.trailing, 12)
                    .padding(.vertical, 6)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .padding(.leading, 12)
            .background(isSelected ? Color.ghostAccentMuted : Color.clear)

            if isExpanded {
                ForEach(domain.paths) { pathItem in
                    PathRow(pathItem: pathItem)
                }
            }
        }
    }
}

// MARK: - Path Row

struct PathRow: View {
    let pathItem: PathItem

    var body: some View {
        HStack(spacing: 6) {
            Text(pathItem.method)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundColor(methodColor(pathItem.method))
                .frame(width: 36, alignment: .leading)

            Text(pathItem.path)
                .font(.system(size: 11))
                .foregroundColor(.ghostTextSecondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            Text("\(pathItem.count)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(.ghostTextMuted)
        }
        .padding(.leading, 30)
        .padding(.trailing, 12)
        .padding(.vertical, 4)
    }

    private func methodColor(_ method: String) -> Color {
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

#Preview {
    DomainListView()
        .preferredColorScheme(.dark)
        .frame(width: 240, height: 300)
        .background(Color.ghostSurface)
}

import SwiftUI
import Combine
import os

private let logger = Logger(subsystem: "corelift.api-ghost", category: "DomainsSidebarView")

struct DomainsSidebarView: View {
    @State private var expandedDomains: Set<String> = []
    @State private var domains: [DomainItem] = []
    @State private var appState = AppState.shared

    private let captureStore = CaptureStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("DOMAINS")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.ghostTextMuted)

                Spacer()

                if !domains.isEmpty {
                    Text("\(totalRequestCount)")
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(.ghostTextMuted)
                }

                Image("AppLogoMark")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 28, height: 28)
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 6)
            .frame(height: 48, alignment: .bottom)

            Divider()
                .background(Color.ghostBorder)

            if domains.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "globe")
                        .font(.system(size: 20))
                        .foregroundColor(.ghostTextMuted)

                    Text("No domains captured")
                        .font(.system(size: 11))
                        .foregroundColor(.ghostTextMuted)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        AllDomainsButton(
                            totalCount: totalRequestCount,
                            isSelected: appState.selectedDomain == nil
                        ) {
                            clearSelection()
                        }

                        Divider()
                            .background(Color.ghostBorder)
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)

                        ForEach(domains) { domain in
                            CompactDomainRow(
                                domain: domain,
                                isSelected: appState.selectedDomain == domain.name
                            ) {
                                selectDomain(domain.name)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.ghostSurface)
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

    // MARK: - Computed Properties

    private var totalRequestCount: Int {
        domains.reduce(0) { $0 + $1.requestCount }
    }

    // MARK: - Actions

    private func loadDomains() {
        Task {
            do {
                let domainCounts = try captureStore.fetchDomains()

                await MainActor.run {
                    domains = domainCounts.map { hostCount in
                        DomainItem(
                            name: hostCount.host,
                            requestCount: hostCount.count,
                            paths: []
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
            if appState.selectedDomain == domain {
                appState.selectedDomain = nil
            } else {
                appState.selectedDomain = domain
            }
        }
    }

    private func clearSelection() {
        withAnimation(.easeInOut(duration: 0.2)) {
            appState.selectedDomain = nil
        }
    }
}

// MARK: - All Domains Button

struct AllDomainsButton: View {
    let totalCount: Int
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Circle()
                    .fill(isSelected ? Color.ghostAccent : Color.ghostTextMuted)
                    .frame(width: 6, height: 6)

                Text("All")
                    .font(.system(size: 12))
                    .foregroundColor(isSelected ? .ghostAccent : .ghostTextPrimary)

                Spacer()

                Text("(\(totalCount))")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(isSelected ? .ghostAccent : .ghostTextSecondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(backgroundColor)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var backgroundColor: Color {
        if isSelected {
            return Color.ghostAccentMuted
        } else if isHovered {
            return Color.ghostSurfaceRaised
        } else {
            return Color.clear
        }
    }
}

// MARK: - Compact Domain Row

struct CompactDomainRow: View {
    let domain: DomainItem
    let isSelected: Bool
    let action: () -> Void

    @State private var isHovered: Bool = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Circle()
                    .fill(isSelected ? Color.ghostAccent : Color.ghostTextMuted.opacity(0.5))
                    .frame(width: 6, height: 6)

                Text(domain.name)
                    .font(.system(size: 11))
                    .foregroundColor(isSelected ? .ghostAccent : .ghostTextPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer()

                Text("\(domain.requestCount)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(isSelected ? .ghostAccent : .ghostTextSecondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .background(backgroundColor)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
    }

    private var backgroundColor: Color {
        if isSelected {
            return Color.ghostAccentMuted
        } else if isHovered {
            return Color.ghostSurfaceRaised
        } else {
            return Color.clear
        }
    }
}

#Preview {
    DomainsSidebarView()
        .preferredColorScheme(.dark)
        .frame(width: 160, height: 400)
}

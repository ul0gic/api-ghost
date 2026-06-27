import SwiftUI
import Combine
import os

private let logger = Logger(subsystem: "corelift.api-ghost", category: "StatsView")

struct StatsView: View {
    @State private var capturedCount: Int = 0
    @State private var filteredCount: Int = 0
    @State private var databaseSize: String = "0 KB"
    @State private var domainCount: Int = 0

    private let captureStore = CaptureStore.shared
    private let databaseManager = DatabaseManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            StatItem(label: "Captured", value: formatNumber(capturedCount))
            StatItem(label: "Filtered", value: formatNumber(filteredCount))
            StatItem(label: "Domains", value: formatNumber(domainCount))
            StatItem(label: "DB Size", value: databaseSize)
        }
        .onAppear {
            refreshStats()
        }
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in
            refreshStats()
        }
        .onReceive(NotificationCenter.default.publisher(for: .clearTrafficList)) { _ in
            Task {
                try? await Task.sleep(for: .milliseconds(500))
                await MainActor.run {
                    refreshStats()
                }
            }
        }
    }

    // MARK: - Private Methods

    private func refreshStats() {
        Task {
            do {
                let total = try captureStore.count()
                let filtered = try captureStore.filteredCount()
                let domains = try captureStore.uniqueDomainCount()
                let size = databaseManager.getDatabaseSize()

                await MainActor.run {
                    capturedCount = total - filtered
                    filteredCount = filtered
                    domainCount = domains
                    databaseSize = size

                    AppState.shared.capturedRequestsCount = capturedCount
                    AppState.shared.filteredRequestsCount = filteredCount
                }
            } catch {
                logger.error("Failed to refresh stats: \(error)")
            }
        }
    }

    private func formatNumber(_ number: Int) -> String {
        if number >= 1_000_000 {
            return String(format: "%.1fM", Double(number) / 1_000_000)
        } else if number >= 1_000 {
            return String(format: "%.1fK", Double(number) / 1_000)
        } else {
            return "\(number)"
        }
    }
}

// MARK: - Stat Item

struct StatItem: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(.ghostTextSecondary)

            Spacer()

            Text(value)
                .font(.system(size: 14, weight: .medium, design: .monospaced))
                .foregroundColor(.ghostAccent)
        }
    }
}

#Preview {
    StatsView()
        .preferredColorScheme(.dark)
        .padding()
        .frame(width: 240)
        .background(Color.ghostSurface)
}

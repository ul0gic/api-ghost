//
//  SQLSchemaBrowserSections.swift
//  APIGhost
//
//  Schema browser child sections: statistics, history, and helper rows.
//

import SwiftUI

// MARK: - Statistics Section

struct SchemaStatisticsSection: View {
    @Bindable var viewModel: SQLViewModel
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: { withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() } }, label: {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.ghostTextMuted)
                        .frame(width: 12)
                    Image(systemName: "chart.bar.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.ghostTextSecondary)
                    Text("STATISTICS")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.ghostTextMuted)
                        .tracking(0.5)
                    Spacer()
                    Button(action: { viewModel.loadStatistics() }, label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 10))
                            .foregroundColor(.ghostTextMuted)
                    })
                    .buttonStyle(.plain)
                    .help("Refresh statistics")
                }
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            })
            .buttonStyle(.plain)

            if isExpanded, let stats = viewModel.tableStatistics {
                VStack(alignment: .leading, spacing: 6) {
                    StatRow(label: "Total Rows", value: "\(stats.totalRows.formatted())")
                    StatRow(label: "DB Size", value: stats.databaseSize)
                    StatRow(label: "Unique Domains", value: "\(stats.uniqueDomains)")
                    StatRow(label: "Unique Paths", value: "\(stats.uniquePaths)")
                    if let oldest = stats.oldestCapture {
                        StatRow(label: "Oldest", value: formatDate(oldest))
                    }
                    if let newest = stats.newestCapture {
                        StatRow(label: "Newest", value: formatDate(newest))
                    }
                }
                .padding(.leading, 18)
                .padding(.top, 4)
            }
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Stat Row

struct StatRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label).font(.system(size: 11)).foregroundColor(.ghostTextMuted)
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(.ghostTextSecondary)
        }
    }
}

// MARK: - History Section

struct SchemaHistorySection: View {
    @Bindable var viewModel: SQLViewModel
    @Binding var isExpanded: Bool
    @State private var hoveredHistoryId: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            historyHeader
            if isExpanded {
                historyContent
            }
        }
    }

    private var historyHeader: some View {
        HStack(spacing: 6) {
            Button(action: { withAnimation(.easeInOut(duration: 0.15)) { isExpanded.toggle() } }, label: {
                HStack(spacing: 6) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(.ghostTextMuted)
                        .frame(width: 12)
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 12))
                        .foregroundColor(.ghostTextSecondary)
                    Text("HISTORY")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.ghostTextMuted)
                        .tracking(0.5)
                }
                .contentShape(Rectangle())
            })
            .buttonStyle(.plain)

            Spacer()

            if !viewModel.queryHistory.isEmpty {
                Text("\(viewModel.queryHistory.count)")
                    .font(.system(size: 10))
                    .foregroundColor(.ghostTextMuted)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.ghostSurfaceRaised)
                    .cornerRadius(4)
                Button(action: { viewModel.clearHistory() }, label: {
                    Image(systemName: "trash")
                        .font(.system(size: 10))
                        .foregroundColor(.ghostTextMuted)
                })
                .buttonStyle(.plain)
                .help("Clear history")
            }
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder private var historyContent: some View {
        if viewModel.queryHistory.isEmpty {
            Text("No query history")
                .font(.system(size: 11))
                .foregroundColor(.ghostTextMuted)
                .italic()
                .padding(.leading, 18)
                .padding(.top, 4)
        } else {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(viewModel.queryHistory.prefix(10)) { item in
                    HistoryRow(
                        item: item, isHovered: hoveredHistoryId == item.id
                    ) { viewModel.restoreQuery(item) }
                    .onHover { hovering in
                        hoveredHistoryId = hovering ? item.id : nil
                    }
                }
            }
            .padding(.leading, 18)
            .padding(.top, 4)
        }
    }
}

// MARK: - History Row

struct HistoryRow: View {
    let item: QueryHistoryItem
    let isHovered: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: item.wasSuccessful ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .font(.system(size: 8))
                        .foregroundColor(item.wasSuccessful ? .ghostSuccess : .ghostError)
                    Text(formatTimestamp(item.timestamp))
                        .font(.system(size: 9))
                        .foregroundColor(.ghostTextMuted)
                    Spacer()
                    if item.wasSuccessful {
                        Text("\(item.rowCount) rows")
                            .font(.system(size: 9))
                            .foregroundColor(.ghostTextMuted)
                    }
                }
                Text(item.query.trimmingCharacters(in: .whitespacesAndNewlines))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.ghostTextSecondary)
                    .lineLimit(2)
                    .truncationMode(.tail)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 6)
            .background(isHovered ? Color.ghostSurfaceRaised : Color.clear)
            .cornerRadius(4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Click to restore this query")
    }

    private func formatTimestamp(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

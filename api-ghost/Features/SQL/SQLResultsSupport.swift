import SwiftUI
import GRDB
import UniformTypeIdentifiers
import os

private let logger = Logger(subsystem: "corelift.api-ghost", category: "SQLResultsView")

// MARK: - Smart Cell (with formatting)

struct SmartCell: View {
    let column: String
    let value: DatabaseValue
    let width: CGFloat
    let isNumeric: Bool

    var body: some View {
        Group {
            if column.lowercased() == "method" {
                if case .string(let method) = value.storage {
                    HStack {
                        MethodBadge(method: method)
                        Spacer()
                    }
                    .padding(.horizontal, 8)
                } else {
                    cellText
                }
            } else if column.lowercased() == "status_code" {
                if case .int64(let code) = value.storage {
                    HStack {
                        Spacer()
                        StatusBadge(statusCode: Int(code))
                    }
                    .padding(.horizontal, 8)
                } else {
                    cellText
                }
            } else if column.lowercased() == "graphql_operation_type" {
                graphQLTypeCell
            } else if column.lowercased() == "graphql_operation_name" {
                graphQLNameCell
            } else if column.lowercased() == "timestamp" {
                timestampCell
            } else {
                cellText
            }
        }
        .frame(width: width - 4, alignment: isNumeric ? .trailing : .leading)
    }

    @ViewBuilder private var graphQLTypeCell: some View {
        if case .string(let type) = value.storage {
            HStack {
                GraphQLOperationBadge(operationType: type)
                Spacer()
            }
            .padding(.horizontal, 8)
        } else {
            cellText
        }
    }

    @ViewBuilder private var graphQLNameCell: some View {
        if case .string(let name) = value.storage {
            Text(name)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.ghostAccent)
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.horizontal, 8)
        } else {
            cellText
        }
    }

    private var cellText: some View {
        let displayValue = SQLQueryResult.formatValueForColumn(value, column: column)
        let fullValue = SQLQueryResult.formatValue(value)

        return Text(displayValue)
            .font(.system(size: 11, design: .monospaced))
            .foregroundColor(cellColor)
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.horizontal, 8)
            .help(fullValue != displayValue ? fullValue : "")
    }

    private var timestampCell: some View {
        let displayValue = SQLQueryResult.formatTimestamp(value)

        return Text(displayValue)
            .font(.system(size: 11, design: .monospaced))
            .foregroundColor(.ghostTextMuted)
            .lineLimit(1)
            .padding(.horizontal, 8)
    }

    private var cellColor: Color {
        switch value.storage {
        case .null: return .ghostTextMuted
        case .int64: return .ghostJsonNumber
        case .double: return .ghostJsonNumber
        case .string: return .ghostTextPrimary
        case .blob: return .ghostTextMuted
        }
    }
}

// MARK: - Results Header

struct ResultsHeader: View {
    @Bindable var viewModel: SQLViewModel
    @Binding var showingExportMenu: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "tablecells")
                .font(.system(size: 11))
                .foregroundColor(.ghostTextMuted)
            Text("Results")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.ghostTextPrimary)
            if let result = viewModel.queryResult {
                Text("\(result.rowCount) rows")
                    .font(.system(size: 11))
                    .foregroundColor(.ghostTextMuted)
            }

            Spacer()

            if viewModel.queryResult != nil {
                exportMenu
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.ghostSurface)
    }

    private var exportMenu: some View {
        Menu {
            Button(action: { exportCSV() }, label: {
                Label("Export as CSV", systemImage: "doc.text")
            })
            Button(action: { exportJSON() }, label: {
                Label("Export as JSON", systemImage: "curlybraces")
            })
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 10))
                Text("Export")
                    .font(.system(size: 11))
            }
            .foregroundColor(.ghostTextSecondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color.ghostSurfaceRaised)
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.ghostBorder, lineWidth: 1)
            )
        }
        .menuStyle(.borderlessButton)
    }

    private func exportCSV() {
        let csv = viewModel.exportToCSV()
        saveToFile(content: csv, extension: "csv")
    }

    private func exportJSON() {
        let json = viewModel.exportToJSON()
        saveToFile(content: json, extension: "json")
    }

    private func saveToFile(content: String, extension ext: String) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = ext == "csv" ? [.commaSeparatedText] : [.json]
        panel.nameFieldStringValue = "query_results.\(ext)"
        panel.begin { response in
            if response == .OK, let url = panel.url {
                do {
                    try content.write(to: url, atomically: true, encoding: .utf8)
                } catch {
                    logger.error("Export failed: \(error)")
                }
            }
        }
    }
}

// MARK: - Row Context Menu

struct RowContextMenu: View {
    let columns: [String]
    let row: [DatabaseValue]

    var body: some View {
        Button("Copy Row as JSON") { copyRowAsJSON() }
        Button("Copy Row as CSV") { copyRowAsCSV() }
        Divider()
        ForEach(Array(columns.enumerated()), id: \.offset) { index, column in
            Button("Copy '\(column)'") {
                let value = SQLQueryResult.formatValue(row[index])
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(value, forType: .string)
            }
        }
    }

    private func copyRowAsJSON() {
        var dict: [String: String] = [:]
        for (index, column) in columns.enumerated() {
            dict[column] = SQLQueryResult.formatValue(row[index])
        }
        if let data = try? JSONSerialization.data(withJSONObject: dict, options: .prettyPrinted),
           let str = String(data: data, encoding: .utf8) {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(str, forType: .string)
        }
    }

    private func copyRowAsCSV() {
        let values = row.map { SQLQueryResult.formatValue($0) }
        let csv = values.joined(separator: ",")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(csv, forType: .string)
    }
}

// MARK: - Pagination Bar

struct PaginationBar: View {
    @Bindable var viewModel: SQLViewModel

    var body: some View {
        HStack(spacing: 12) {
            Text("Page \(viewModel.currentPage) of \(viewModel.totalPages)")
                .font(.system(size: 11))
                .foregroundColor(.ghostTextSecondary)
            Spacer()
            paginationControls
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.ghostSurface)
    }

    private var paginationControls: some View {
        HStack(spacing: 4) {
            pageButton(icon: "chevron.left.2", disabled: viewModel.currentPage == 1) {
                viewModel.goToPage(1)
            }
            pageButton(icon: "chevron.left", disabled: viewModel.currentPage == 1) {
                viewModel.previousPage()
            }

            ForEach(pageNumbers, id: \.self) { page in
                pageNumberButton(page: page)
            }

            pageButton(icon: "chevron.right", disabled: viewModel.currentPage == viewModel.totalPages) {
                viewModel.nextPage()
            }
            pageButton(icon: "chevron.right.2", disabled: viewModel.currentPage == viewModel.totalPages) {
                viewModel.goToPage(viewModel.totalPages)
            }
        }
    }

    private func pageNumberButton(page: Int) -> some View {
        let isCurrent = page == viewModel.currentPage
        return Button { viewModel.goToPage(page) } label: {
            Text("\(page)")
                .font(.system(size: 11, weight: isCurrent ? .semibold : .regular))
                .foregroundColor(isCurrent ? .ghostAccent : .ghostTextSecondary)
                .frame(width: 24, height: 24)
                .background(isCurrent ? Color.ghostAccentMuted : Color.clear)
                .cornerRadius(4)
        }
        .buttonStyle(.plain)
    }

    private func pageButton(icon: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 10))
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .foregroundColor(disabled ? .ghostTextMuted : .ghostTextSecondary)
    }

    private var pageNumbers: [Int] {
        let total = viewModel.totalPages
        let current = viewModel.currentPage
        var pages: [Int] = []
        for page in max(1, current - 2)...min(total, current + 2) {
            pages.append(page)
        }
        return pages
    }
}

// MARK: - Status Bar

struct ResultsStatusBar: View {
    @Bindable var viewModel: SQLViewModel

    var body: some View {
        HStack(spacing: 16) {
            if let result = viewModel.queryResult {
                statusItems(for: result)
            } else if let error = viewModel.errorMessage {
                errorDisplay(error)
            } else {
                Text("Ready")
                    .font(.system(size: 11))
                    .foregroundColor(.ghostTextMuted)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.ghostSurface)
        .overlay(
            Rectangle().frame(height: 1).foregroundColor(Color.ghostBorder),
            alignment: .top
        )
    }

    private func statusItems(for result: SQLQueryResult) -> some View {
        Group {
            HStack(spacing: 4) {
                Image(systemName: "clock").font(.system(size: 10)).foregroundColor(.ghostTextMuted)
                Text(String(format: "%.2f ms", result.executionTimeMs))
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.ghostTextSecondary)
            }
            HStack(spacing: 4) {
                Image(systemName: "number").font(.system(size: 10)).foregroundColor(.ghostTextMuted)
                Text("\(result.rowCount) rows returned")
                    .font(.system(size: 11))
                    .foregroundColor(.ghostTextSecondary)
            }
            HStack(spacing: 4) {
                Image(systemName: "calendar").font(.system(size: 10)).foregroundColor(.ghostTextMuted)
                Text(formatDate(result.timestamp))
                    .font(.system(size: 11))
                    .foregroundColor(.ghostTextMuted)
            }
        }
    }

    private func errorDisplay(_ error: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10)).foregroundColor(.ghostError)
            Text(error)
                .font(.system(size: 11)).foregroundColor(.ghostError).lineLimit(1)
        }
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
}

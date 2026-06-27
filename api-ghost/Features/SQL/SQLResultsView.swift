//
//  SQLResultsView.swift
//  APIGhost
//
//  Results table view for SQL query results with resizable columns, sorting, pagination, and export.
//

import SwiftUI
import GRDB

// MARK: - SQL Results View

struct SQLResultsView: View {
    @Bindable var viewModel: SQLViewModel
    @State private var hoveredRowIndex: Int?
    @State private var hoveredColumnIndex: Int?
    @State private var showingExportMenu: Bool = false
    @State private var showingCaptureDetail: Bool = false
    @State private var selectedCapture: Capture?

    var body: some View {
        VStack(spacing: 0) {
            ResultsHeader(viewModel: viewModel, showingExportMenu: $showingExportMenu)
            Divider().background(Color.ghostBorder)

            if let result = viewModel.queryResult {
                if result.rows.isEmpty {
                    EmptyResultsView()
                } else {
                    resultsTable(result: result)
                }
            } else if viewModel.isExecuting {
                ExecutingView()
            } else {
                NoQueryView()
            }

            ResultsStatusBar(viewModel: viewModel)
        }
        .background(Color.ghostBase)
        .sheet(isPresented: $showingCaptureDetail) {
            if let capture = selectedCapture {
                SQLCaptureDetailView(capture: capture) { showingCaptureDetail = false }
            }
        }
        .sheet(isPresented: $viewModel.showingRowDetail) {
            if let result = viewModel.queryResult, let row = viewModel.selectedRow {
                RowDetailSheet(
                    columns: result.columns, row: row
                ) { viewModel.showingRowDetail = false }
            }
        }
    }

    private func resultsTable(result: SQLQueryResult) -> some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                ResizableTableView(
                    columns: result.columns,
                    rows: viewModel.displayedRows,
                    viewModel: viewModel,
                    hoveredRowIndex: $hoveredRowIndex,
                    hoveredColumnIndex: $hoveredColumnIndex,
                    onRowTap: { rowIndex in
                        handleRowTap(
                            rowIndex: rowIndex,
                            columns: result.columns,
                            row: viewModel.displayedRows[rowIndex]
                        )
                    },
                    containerWidth: geometry.size.width
                )
            }

            if viewModel.totalPages > 1 {
                Divider().background(Color.ghostBorder)
                PaginationBar(viewModel: viewModel)
            }
        }
    }

    private func handleRowTap(rowIndex: Int, columns: [String], row: [DatabaseValue]) {
        if let idIndex = columns.firstIndex(where: { $0.lowercased() == "id" }) {
            if case .int64(let captureId) = row[idIndex].storage {
                Task {
                    if let capture = await viewModel.fetchCapture(byId: captureId) {
                        await MainActor.run {
                            selectedCapture = capture
                            showingCaptureDetail = true
                        }
                    } else {
                        await MainActor.run {
                            viewModel.selectedRowIndex = rowIndex
                            viewModel.showingRowDetail = true
                        }
                    }
                }
            }
        } else {
            viewModel.selectedRowIndex = rowIndex
            viewModel.showingRowDetail = true
        }
    }
}

// MARK: - Preview

#Preview {
    SQLResultsView(viewModel: SQLViewModel())
        .preferredColorScheme(.dark)
        .frame(width: 800, height: 500)
}

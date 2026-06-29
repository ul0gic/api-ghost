import SwiftUI
import os

private let logger = Logger(subsystem: "corelift.api-ghost", category: "SQLViewModel")
@preconcurrency import GRDB

// MARK: - SQL ViewModel

@Observable
final class SQLViewModel {
    // MARK: - Properties

    var queryText: String = ""

    var queryResult: SQLQueryResult?

    var errorMessage: String?

    var isExecuting: Bool = false

    var queryHistory: [QueryHistoryItem] = []

    var schemaColumns: [SchemaColumn] = []
    var schemaIndexes: [SchemaIndex] = []
    var tableStatistics: TableStatistics?

    var currentPage: Int = 1
    var rowsPerPage: Int = 100
    var totalResultRows: Int = 0

    var sortConfig = SortConfiguration()

    var queryRowLimit: Int = 1000

    var queryBuilderFilters: [QueryBuilderFilter] = []

    var timeRangeFilter: TimeRangeFilter = .all

    var showQueryBuilder: Bool = false

    var columnWidths: [String: CGFloat] = [:]

    var selectedCaptureId: Int64?

    // MARK: - Default Columns for API Analysis

    static let defaultAPIColumns: [String] = [
        "id", "method", "host", "path", "status_code",
        "content_type", "response_body_size", "duration_ms", "timestamp"
    ]

    static let numericColumns: Set<String> = [
        "id", "status_code", "response_body_size", "duration_ms",
        "request_body_size", "port", "request_count", "avg_duration_ms", "total_bytes"
    ]

    // MARK: - Computed Properties

    var totalPages: Int {
        guard totalResultRows > 0 else { return 1 }
        return Int(ceil(Double(totalResultRows) / Double(rowsPerPage)))
    }

    var displayedRows: [[DatabaseValue]] {
        guard let result = queryResult else { return [] }

        var rows = result.rows

        if let columnIndex = sortConfig.columnIndex, columnIndex < result.columns.count {
            rows = rows.sorted { row1, row2 in
                let val1 = row1[columnIndex]
                let val2 = row2[columnIndex]
                let comparison = compareValues(val1, val2)
                return sortConfig.ascending ? comparison : !comparison
            }
        }

        let startIndex = (currentPage - 1) * rowsPerPage
        let endIndex = min(startIndex + rowsPerPage, rows.count)

        guard startIndex < rows.count else { return [] }
        return Array(rows[startIndex..<endIndex])
    }

    // MARK: - Initialization

    init() {
        loadSchema()
        loadStatistics()
        loadQueryHistory()
        loadColumnWidths()
    }

    // MARK: - Query Execution

    func executeQuery() {
        guard !queryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Query cannot be empty"
            return
        }

        guard let db = DatabaseManager.shared.database else {
            errorMessage = "Database not available"
            return
        }

        isExecuting = true
        errorMessage = nil
        queryResult = nil
        currentPage = 1
        sortConfig = SortConfiguration()

        let startTime = CFAbsoluteTimeGetCurrent()
        let queryToExecute = queryText.trimmingCharacters(in: .whitespacesAndNewlines)

        Task { @MainActor in
            do {
                let result = try await runQuery(queryToExecute, on: db, startTime: startTime)
                self.queryResult = result
                self.totalResultRows = result.rowCount
                self.addToHistory(
                    query: queryToExecute,
                    executionTime: result.executionTimeMs,
                    rowCount: result.rowCount,
                    success: true
                )
            } catch {
                self.errorMessage = error.localizedDescription
                self.addToHistory(
                    query: queryToExecute, executionTime: 0, rowCount: 0, success: false
                )
            }
            self.isExecuting = false
        }
    }

    private func runQuery(
        _ queryToExecute: String,
        on db: DatabaseQueue,
        startTime: CFAbsoluteTime
    ) async throws -> SQLQueryResult {
        typealias ResultContinuation = CheckedContinuation<SQLQueryResult, Error>
        let finalQuery = applyQueryLimit(to: queryToExecute)
        return try await withCheckedThrowingContinuation { (continuation: ResultContinuation) in
            DispatchQueue.global(qos: .userInitiated).async {
                do {
                    let result = try db.read { db -> SQLQueryResult in
                        try self.executeAndCollect(
                            finalQuery, on: db, startTime: startTime, originalQuery: queryToExecute
                        )
                    }
                    continuation.resume(returning: result)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func applyQueryLimit(to query: String) -> String {
        let upperQuery = query.uppercased()
        if upperQuery.hasPrefix("SELECT") && !upperQuery.contains("LIMIT") {
            return query + " LIMIT \(queryRowLimit)"
        }
        return query
    }

    nonisolated private func executeAndCollect(
        _ finalQuery: String,
        on db: GRDB.Database,
        startTime: CFAbsoluteTime,
        originalQuery: String
    ) throws -> SQLQueryResult {
        let statement = try db.makeStatement(sql: finalQuery)
        let columns = statement.columnNames

        var rows: [[DatabaseValue]] = []
        let cursor = try Row.fetchCursor(statement)
        while let row = try cursor.next() {
            rows.append((0..<columns.count).map { row[$0] })
        }

        let executionTime = (CFAbsoluteTimeGetCurrent() - startTime) * 1000
        return SQLQueryResult(
            columns: columns,
            rows: rows,
            rowCount: rows.count,
            executionTimeMs: executionTime,
            query: originalQuery,
            timestamp: Date()
        )
    }

    func executeQuickQuery(_ type: QuickQueryType) {
        queryText = type.sql
        executeQuery()
    }

    // MARK: - Schema Loading

    func loadSchema() {
        guard let db = DatabaseManager.shared.database else { return }

        do {
            try db.read { db in
                let columnRows = try Row.fetchAll(db, sql: "PRAGMA table_info(captures)")
                schemaColumns = columnRows.map { row in
                    SchemaColumn(
                        name: row["name"] ?? "",
                        type: row["type"] ?? "",
                        isNotNull: row["notnull"] == 1,
                        isPrimaryKey: row["pk"] == 1,
                        defaultValue: row["dflt_value"]
                    )
                }

                let indexRows = try Row.fetchAll(db, sql: "PRAGMA index_list(captures)")
                schemaIndexes = indexRows.compactMap { row -> SchemaIndex? in
                    guard let indexName: String = row["name"] else { return nil }
                    let isUnique: Bool = row["unique"] == 1

                    let columnRows = try? Row.fetchAll(db, sql: "PRAGMA index_info('\(indexName)')")
                    let columns = columnRows?.compactMap { $0["name"] as? String } ?? []

                    return SchemaIndex(
                        name: indexName,
                        columns: columns,
                        isUnique: isUnique
                    )
                }
            }
        } catch {
            logger.error("Failed to load schema: \(error)")
        }
    }

    func loadStatistics() {
        guard let db = DatabaseManager.shared.database else { return }

        do {
            try db.read { db in
                let totalRows = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM captures") ?? 0
                let uniqueDomains = try Int.fetchOne(db, sql: "SELECT COUNT(DISTINCT host) FROM captures") ?? 0
                let uniquePaths = try Int.fetchOne(db, sql: "SELECT COUNT(DISTINCT path) FROM captures") ?? 0
                let oldest = try Date.fetchOne(db, sql: "SELECT MIN(timestamp) FROM captures")
                let newest = try Date.fetchOne(db, sql: "SELECT MAX(timestamp) FROM captures")

                let dbSize = DatabaseManager.shared.getDatabaseSize()

                tableStatistics = TableStatistics(
                    totalRows: totalRows,
                    databaseSize: dbSize,
                    uniqueDomains: uniqueDomains,
                    uniquePaths: uniquePaths,
                    oldestCapture: oldest,
                    newestCapture: newest
                )
            }
        } catch {
            logger.error("Failed to load statistics: \(error)")
        }
    }

    // MARK: - Query History

    private func loadQueryHistory() {
        if let data = UserDefaults.standard.data(forKey: "SQLQueryHistory"),
           let history = try? JSONDecoder().decode([QueryHistoryItem].self, from: data) {
            queryHistory = history
        }
    }

    private func saveQueryHistory() {
        let historyToSave = Array(queryHistory.prefix(50))
        if let data = try? JSONEncoder().encode(historyToSave) {
            UserDefaults.standard.set(data, forKey: "SQLQueryHistory")
        }
    }

    private func addToHistory(query: String, executionTime: Double, rowCount: Int, success: Bool) {
        let item = QueryHistoryItem(
            query: query,
            executionTimeMs: executionTime,
            rowCount: rowCount,
            wasSuccessful: success
        )
        queryHistory.insert(item, at: 0)
        saveQueryHistory()
    }

    func clearHistory() {
        queryHistory.removeAll()
        saveQueryHistory()
    }

    func restoreQuery(_ item: QueryHistoryItem) {
        queryText = item.query
    }

    // MARK: - Sorting

    func toggleSort(for columnIndex: Int) {
        if sortConfig.columnIndex == columnIndex {
            sortConfig.ascending.toggle()
        } else {
            sortConfig.columnIndex = columnIndex
            sortConfig.ascending = true
        }
    }

    // MARK: - Pagination

    func goToPage(_ page: Int) {
        guard page >= 1 && page <= totalPages else { return }
        currentPage = page
    }

    func nextPage() {
        goToPage(currentPage + 1)
    }

    func previousPage() {
        goToPage(currentPage - 1)
    }
}

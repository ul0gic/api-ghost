//
//  SQLViewModel+Extensions.swift
//  APIGhost
//
//  Extensions for SQLViewModel: query builder, column management, export, and helpers.
//

import SwiftUI
import os
@preconcurrency import GRDB

private let logger = Logger(subsystem: "corelift.api-ghost", category: "SQLViewModel")

// MARK: - Export

extension SQLViewModel {
    func exportToCSV() -> String {
        guard let result = queryResult else { return "" }

        var csv = result.columns.joined(separator: ",") + "\n"

        for row in result.rows {
            let values = row.map { value -> String in
                let str = SQLQueryResult.formatValue(value)
                if str.contains(",") || str.contains("\"") || str.contains("\n") {
                    return "\"\(str.replacingOccurrences(of: "\"", with: "\"\""))\""
                }
                return str
            }
            csv += values.joined(separator: ",") + "\n"
        }

        return csv
    }

    func exportToJSON() -> String {
        guard let result = queryResult else { return "[]" }

        var jsonArray: [[String: Any]] = []

        for row in result.rows {
            var dict: [String: Any] = [:]
            for (index, column) in result.columns.enumerated() {
                let value = row[index]
                switch value.storage {
                case .null:
                    dict[column] = NSNull()
                case .int64(let int):
                    dict[column] = int
                case .double(let double):
                    dict[column] = double
                case .string(let string):
                    dict[column] = string
                case .blob(let data):
                    dict[column] = data.base64EncodedString()
                }
            }
            jsonArray.append(dict)
        }

        if let data = try? JSONSerialization.data(
            withJSONObject: jsonArray,
            options: .prettyPrinted
        ),
           let string = String(data: data, encoding: .utf8) {
            return string
        }

        return "[]"
    }
}

// MARK: - Helpers

extension SQLViewModel {
    func insertColumnName(_ column: String) {
        if queryText.isEmpty {
            queryText = column
        } else {
            queryText += " " + column
        }
    }

    func generateSelectQuery(for table: String) {
        queryText = "SELECT * FROM \(table) LIMIT 100"
    }

    func formatQuery() {
        var formatted = queryText

        let keywords = [
            "SELECT", "FROM", "WHERE", "AND", "OR", "ORDER BY", "GROUP BY",
            "HAVING", "LIMIT", "OFFSET", "JOIN", "LEFT JOIN", "RIGHT JOIN",
            "INNER JOIN", "ON", "AS", "DISTINCT", "COUNT", "SUM", "AVG",
            "MAX", "MIN", "INSERT", "UPDATE", "DELETE", "INTO", "VALUES",
            "SET", "CREATE", "DROP", "ALTER", "TABLE", "INDEX", "NOT", "NULL",
            "LIKE", "IN", "BETWEEN", "IS", "ASC", "DESC"
        ]

        for keyword in keywords {
            let pattern = "\\b\(keyword)\\b"
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                let range = NSRange(formatted.startIndex..., in: formatted)
                formatted = regex.stringByReplacingMatches(
                    in: formatted,
                    range: range,
                    withTemplate: keyword
                )
            }
        }

        queryText = formatted
    }

    func clearQuery() {
        queryText = ""
        queryResult = nil
        errorMessage = nil
        currentPage = 1
        sortConfig = SortConfiguration()
    }
}

// MARK: - Query Builder

extension SQLViewModel {
    func addFilter() {
        let filter = QueryBuilderFilter(
            field: .pathPattern,
            operation: .contains,
            value: ""
        )
        queryBuilderFilters.append(filter)
    }

    func removeFilter(_ filter: QueryBuilderFilter) {
        queryBuilderFilters.removeAll { $0.id == filter.id }
    }

    func clearFilters() {
        queryBuilderFilters.removeAll()
        timeRangeFilter = .all
    }

    func buildQueryFromFilters() {
        var conditions: [String] = []

        if let timeCondition = timeRangeFilter.sqlCondition {
            conditions.append(timeCondition)
        }

        for filter in queryBuilderFilters where filter.isValid {
            let column = filter.field.sqlColumn
            let op = filter.operation.sqlOperator
            let value = filter.operation.formatValue(filter.value)

            if filter.field == .responseContains || filter.field == .requestContains {
                conditions.append("CAST(\(column) AS TEXT) \(op) \(value)")
            } else {
                conditions.append("\(column) \(op) \(value)")
            }
        }

        var query = """
            SELECT id, method, host, path, status_code, content_type,
                   response_body_size, duration_ms, timestamp
            FROM captures
            """

        if !conditions.isEmpty {
            query += "\nWHERE " + conditions.joined(separator: "\n  AND ")
        }

        query += "\nORDER BY timestamp DESC\nLIMIT 100"

        queryText = query
    }

    func executeQueryFromFilters() {
        buildQueryFromFilters()
        executeQuery()
    }
}

// MARK: - Column Width Management

extension SQLViewModel {
    func columnWidth(for column: String) -> CGFloat {
        if let width = columnWidths[column] {
            return width
        }
        return defaultColumnWidth(for: column)
    }

    func setColumnWidth(_ width: CGFloat, for column: String) {
        columnWidths[column] = width
        saveColumnWidths()
    }

    private static let columnWidthDefaults: [String: CGFloat] = [
        "id": 50, "method": 70, "status_code": 70,
        "host": 160, "path": 220, "content_type": 80,
        "timestamp": 100, "duration_ms": 80,
        "response_body_size": 90, "request_body_size": 90,
        "request_count": 90, "avg_duration_ms": 100, "total_bytes": 90
    ]

    func defaultColumnWidth(for column: String) -> CGFloat {
        Self.columnWidthDefaults[column.lowercased()] ?? max(100, CGFloat(column.count * 9))
    }

    func isNumericColumn(_ column: String) -> Bool {
        Self.numericColumns.contains(column.lowercased())
    }
}

// MARK: - Fetch Capture

extension SQLViewModel {
    func fetchCapture(byId captureId: Int64) async -> Capture? {
        guard let db = DatabaseManager.shared.database else { return nil }

        do {
            return try await MainActor.run {
                try db.read { db in
                    try Capture.fetchOne(db, key: captureId)
                }
            }
        } catch {
            logger.error("Failed to fetch capture: \(error)")
            return nil
        }
    }
}

// MARK: - Value Comparison

extension SQLViewModel {
    func compareValues(_ val1: DatabaseValue, _ val2: DatabaseValue) -> Bool {
        switch (val1.storage, val2.storage) {
        case (.null, _):
            return true
        case (_, .null):
            return false
        case let (.int64(lhs), .int64(rhs)):
            return lhs < rhs
        case let (.double(lhs), .double(rhs)):
            return lhs < rhs
        case let (.string(lhs), .string(rhs)):
            return lhs.localizedCompare(rhs) == .orderedAscending
        default:
            return false
        }
    }

    func loadColumnWidths() {
        if let data = UserDefaults.standard.data(forKey: "SQLColumnWidths"),
           let widths = try? JSONDecoder().decode([String: CGFloat].self, from: data) {
            columnWidths = widths
        }
    }

    func saveColumnWidths() {
        if let data = try? JSONEncoder().encode(columnWidths) {
            UserDefaults.standard.set(data, forKey: "SQLColumnWidths")
        }
    }
}

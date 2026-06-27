import Foundation
@preconcurrency import GRDB

// MARK: - SQL Query Result

struct SQLQueryResult: Identifiable {
    let id = UUID()
    let columns: [String]
    let rows: [[DatabaseValue]]
    let rowCount: Int
    let executionTimeMs: Double
    let query: String
    let timestamp: Date

    func value(row: Int, column: Int) -> DatabaseValue? {
        guard row < rows.count, column < columns.count else { return nil }
        return rows[row][column]
    }

    static func formatValue(_ value: DatabaseValue) -> String {
        switch value.storage {
        case .null:
            return "NULL"
        case .int64(let int):
            return String(int)
        case .double(let double):
            return String(format: "%.4f", double)
        case .string(let string):
            if string.count > 100 {
                return String(string.prefix(100)) + "..."
            }
            return string
        case .blob(let data):
            return "<BLOB \(data.count) bytes>"
        }
    }

    static func formatValueForColumn(
        _ value: DatabaseValue,
        column: String
    ) -> String {
        let columnLower = column.lowercased()
        let isSizeColumn = columnLower.contains("size") || columnLower.contains("bytes")
        let isDurationColumn = columnLower.contains("duration")

        switch value.storage {
        case .null:
            return "-"
        case .int64(let int):
            return formatNumericValue(Int(int), isSize: isSizeColumn, isDuration: isDurationColumn)
        case .double(let double):
            return formatDoubleValue(double, isSize: isSizeColumn, isDuration: isDurationColumn)
        case .string(let string):
            return formatStringValue(string, columnLower: columnLower)
        case .blob(let data):
            return "<\(formatBytes(data.count))>"
        }
    }

    private static func formatNumericValue(_ value: Int, isSize: Bool, isDuration: Bool) -> String {
        if isSize { return formatBytes(value) }
        if isDuration { return formatDuration(value) }
        return String(value)
    }

    private static func formatDoubleValue(_ value: Double, isSize: Bool, isDuration: Bool) -> String {
        if isSize { return formatBytes(Int(value)) }
        if isDuration { return formatDuration(Int(value)) }
        return String(format: "%.2f", value)
    }

    private static func formatStringValue(_ string: String, columnLower: String) -> String {
        if columnLower == "content_type" { return shortenContentType(string) }
        if string.count > 60 { return String(string.prefix(57)) + "..." }
        return string
    }

    static func formatBytes(_ bytes: Int) -> String {
        if bytes == 0 { return "-" }
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 {
            return String(format: "%.1f KB", Double(bytes) / 1024)
        }
        return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
    }

    static func formatDuration(_ ms: Int) -> String {
        if ms == 0 { return "-" }
        if ms < 1000 { return "\(ms) ms" }
        return String(format: "%.1f s", Double(ms) / 1000)
    }

    static func shortenContentType(_ contentType: String) -> String {
        let lower = contentType.lowercased()
        let contentTypeMap: [(String, String)] = [
            ("json", "json"), ("html", "html"), ("xml", "xml"),
            ("javascript", "js"), ("js", "js"), ("css", "css"),
            ("png", "png"), ("jpeg", "jpeg"), ("jpg", "jpeg"),
            ("gif", "gif"), ("webp", "webp"), ("svg", "svg"),
            ("plain", "text"), ("octet-stream", "binary"),
            ("form-urlencoded", "form"), ("multipart", "multipart")
        ]
        for (pattern, result) in contentTypeMap where lower.contains(pattern) {
            return result
        }
        if let slashIndex = contentType.firstIndex(of: "/") {
            let subtype = String(contentType[contentType.index(after: slashIndex)...])
            if let semicolonIndex = subtype.firstIndex(of: ";") {
                return String(subtype[..<semicolonIndex])
            }
            return subtype.count > 15 ? String(subtype.prefix(12)) + "..." : subtype
        }
        return contentType.count > 15 ? String(contentType.prefix(12)) + "..." : contentType
    }

    static func formatTimestamp(_ value: DatabaseValue) -> String {
        switch value.storage {
        case .string(let string):
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = formatter.date(from: string) {
                return formatRelativeTime(date)
            }
            formatter.formatOptions = [.withInternetDateTime]
            if let date = formatter.date(from: string) {
                return formatRelativeTime(date)
            }
            return string
        case .double(let timestamp):
            let date = Date(timeIntervalSince1970: timestamp)
            return formatRelativeTime(date)
        case .int64(let timestamp):
            let date = Date(timeIntervalSince1970: Double(timestamp))
            return formatRelativeTime(date)
        default:
            return formatValue(value)
        }
    }

    static func formatRelativeTime(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "just now" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        if interval < 86400 { return "\(Int(interval / 3600))h ago" }
        if interval < 604800 { return "\(Int(interval / 86400))d ago" }
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Query Builder Filter

struct QueryBuilderFilter: Identifiable, Equatable {
    let id = UUID()
    var field: QueryFilterField
    var operation: QueryFilterOperation
    var value: String

    var isValid: Bool {
        !value.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

enum QueryFilterField: String, CaseIterable {
    case contentType = "Content Type"
    case responseContains = "Response Contains"
    case requestContains = "Request Contains"
    case pathPattern = "Path Pattern"
    case host = "Host"
    case sizeMin = "Min Size"
    case sizeMax = "Max Size"
    case durationMin = "Min Duration"
    case durationMax = "Max Duration"
    case method = "Method"
    case statusCode = "Status Code"

    var sqlColumn: String {
        switch self {
        case .contentType: return "content_type"
        case .responseContains: return "response_body"
        case .requestContains: return "request_body"
        case .pathPattern: return "path"
        case .host: return "host"
        case .sizeMin, .sizeMax: return "response_body_size"
        case .durationMin, .durationMax: return "duration_ms"
        case .method: return "method"
        case .statusCode: return "status_code"
        }
    }
}

enum QueryFilterOperation: String, CaseIterable {
    case equals = "equals"
    case contains = "contains"
    case startsWith = "starts with"
    case endsWith = "ends with"
    case greaterThan = ">"
    case lessThan = "<"
    case like = "LIKE"

    var sqlOperator: String {
        switch self {
        case .equals: return "="
        case .contains: return "LIKE"
        case .startsWith: return "LIKE"
        case .endsWith: return "LIKE"
        case .greaterThan: return ">"
        case .lessThan: return "<"
        case .like: return "LIKE"
        }
    }

    func formatValue(_ value: String) -> String {
        switch self {
        case .equals: return "'\(value)'"
        case .contains: return "'%\(value)%'"
        case .startsWith: return "'\(value)%'"
        case .endsWith: return "'%\(value)'"
        case .greaterThan, .lessThan: return value
        case .like: return "'\(value)'"
        }
    }
}

// MARK: - Schema Info

struct SchemaColumn: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let type: String
    let isNotNull: Bool
    let isPrimaryKey: Bool
    let defaultValue: String?
}

struct SchemaIndex: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let columns: [String]
    let isUnique: Bool
}

struct TableStatistics {
    let totalRows: Int
    let databaseSize: String
    let uniqueDomains: Int
    let uniquePaths: Int
    let oldestCapture: Date?
    let newestCapture: Date?
}

// MARK: - Query History Item

struct QueryHistoryItem: Identifiable, Codable {
    let id: UUID
    let query: String
    let timestamp: Date
    let executionTimeMs: Double
    let rowCount: Int
    let wasSuccessful: Bool

    init(query: String, executionTimeMs: Double, rowCount: Int, wasSuccessful: Bool) {
        self.id = UUID()
        self.query = query
        self.timestamp = Date()
        self.executionTimeMs = executionTimeMs
        self.rowCount = rowCount
        self.wasSuccessful = wasSuccessful
    }
}

// MARK: - Sort Configuration

struct SortConfiguration {
    var columnIndex: Int?
    var ascending: Bool = true
}

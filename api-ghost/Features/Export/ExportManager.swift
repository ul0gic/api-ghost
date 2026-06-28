import Foundation
import GRDB
import os

nonisolated private let logger = Logger(subsystem: "corelift.api-ghost", category: "ExportManager")

// MARK: - Export Manager

nonisolated final class ExportManager: Sendable {
    // MARK: - Singleton

    static let shared = ExportManager()

    private init() {}

    // MARK: - Export Methods

    func export(
        to url: URL,
        format: ExportFormat,
        includeHeaders: Bool = true,
        includeBodies: Bool = true,
        includeFiltered: Bool = false
    ) throws {
        switch format {
        case .sqlite:
            try exportSQLite(to: url)
        case .json:
            try exportJSON(
                to: url,
                includeHeaders: includeHeaders,
                includeBodies: includeBodies,
                includeFiltered: includeFiltered
            )
        case .har:
            try exportHAR(
                to: url,
                includeHeaders: includeHeaders,
                includeBodies: includeBodies,
                includeFiltered: includeFiltered
            )
        }
    }

    // MARK: - SQLite Export

    private func exportSQLite(to url: URL) throws {
        guard let sourcePath = DatabaseManager.shared.path,
              let db = DatabaseManager.shared.database else {
            throw ExportError.databaseNotAvailable
        }

        // GRDB 7 writes are immediate transactions; a TRUNCATE checkpoint must run outside one.
        try db.writeWithoutTransaction { db in
            try db.execute(sql: "PRAGMA wal_checkpoint(TRUNCATE)")
        }
        logger.info("WAL checkpoint completed")
        let fileManager = FileManager.default
        let sourceURL = URL(fileURLWithPath: sourcePath)

        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }

        try fileManager.copyItem(at: sourceURL, to: url)

        logger.info("SQLite exported to: \(url.path)")
    }

    // MARK: - JSON Export

    private func exportJSON(
        to url: URL,
        includeHeaders: Bool,
        includeBodies: Bool,
        includeFiltered: Bool
    ) throws {
        let captures = try fetchCaptures(includeFiltered: includeFiltered)

        let exportData = captures.map { capture in
            buildJSONEntry(
                capture: capture,
                includeHeaders: includeHeaders,
                includeBodies: includeBodies
            )
        }

        let jsonData = try JSONSerialization.data(
            withJSONObject: exportData,
            options: [.prettyPrinted, .sortedKeys]
        )

        try jsonData.write(to: url)

        logger.info("JSON exported to: \(url.path)")
    }

    private func buildJSONEntry(
        capture: Capture,
        includeHeaders: Bool,
        includeBodies: Bool
    ) -> [String: Any] {
        var dict: [String: Any] = [
            "uuid": capture.uuid,
            "timestamp": ISO8601DateFormatter().string(from: capture.timestamp),
            "method": capture.method,
            "scheme": capture.scheme,
            "host": capture.host,
            "path": capture.path,
            "url": capture.fullURL
        ]

        addOptionalFields(to: &dict, from: capture)
        addSizeFields(to: &dict, from: capture)

        if includeHeaders {
            addHeaderFields(to: &dict, from: capture)
        }

        if includeBodies {
            addBodyFields(to: &dict, from: capture)
        }

        return dict
    }

    private func addOptionalFields(to dict: inout [String: Any], from capture: Capture) {
        if let port = capture.port { dict["port"] = port }
        if let query = capture.query { dict["query"] = query }
        if let sessionId = capture.sessionId { dict["sessionId"] = sessionId }
        if let statusCode = capture.statusCode { dict["statusCode"] = statusCode }
        if let statusMessage = capture.statusMessage { dict["statusMessage"] = statusMessage }
        if let contentType = capture.contentType { dict["contentType"] = contentType }
        if let durationMs = capture.durationMs { dict["durationMs"] = durationMs }
    }

    private func addSizeFields(to dict: inout [String: Any], from capture: Capture) {
        dict["requestBodySize"] = capture.requestBodySize
        dict["responseBodySize"] = capture.responseBodySize
    }

    private func addHeaderFields(to dict: inout [String: Any], from capture: Capture) {
        if let requestHeaders = capture.requestHeaders {
            dict["requestHeaders"] = try? JSONSerialization.jsonObject(
                with: Data(requestHeaders.utf8)
            )
        }
        if let responseHeaders = capture.responseHeaders {
            dict["responseHeaders"] = try? JSONSerialization.jsonObject(
                with: Data(responseHeaders.utf8)
            )
        }
    }

    private func addBodyFields(to dict: inout [String: Any], from capture: Capture) {
        if let requestBody = capture.requestBody,
           let bodyString = String(data: requestBody, encoding: .utf8) {
            dict["requestBody"] = bodyString
        }
        if let responseBody = capture.responseBody,
           let bodyString = String(data: responseBody, encoding: .utf8) {
            dict["responseBody"] = bodyString
        }
    }

    // MARK: - HAR Export

    private func exportHAR(
        to url: URL,
        includeHeaders: Bool,
        includeBodies: Bool,
        includeFiltered: Bool
    ) throws {
        let captures = try fetchCaptures(includeFiltered: includeFiltered)

        let entries = captures.map { capture in
            buildHAREntry(capture: capture, includeHeaders: includeHeaders, includeBodies: includeBodies)
        }

        let har: [String: Any] = [
            "log": [
                "version": "1.2",
                "creator": ["name": "APIGhost", "version": "1.0"],
                "entries": entries
            ]
        ]

        let jsonData = try JSONSerialization.data(withJSONObject: har, options: [.prettyPrinted])
        try jsonData.write(to: url)
        logger.info("HAR exported to: \(url.path)")
    }

    private func buildHAREntry(
        capture: Capture,
        includeHeaders: Bool,
        includeBodies: Bool
    ) -> [String: Any] {
        var entry: [String: Any] = [
            "startedDateTime": ISO8601DateFormatter().string(from: capture.timestamp),
            "time": capture.durationMs ?? 0
        ]

        entry["request"] = buildHARRequest(
            capture: capture, includeHeaders: includeHeaders, includeBodies: includeBodies
        )
        entry["response"] = buildHARResponse(
            capture: capture, includeHeaders: includeHeaders, includeBodies: includeBodies
        )
        entry["cache"] = [:]
        entry["timings"] = ["send": 0, "wait": capture.durationMs ?? 0, "receive": 0]

        return entry
    }

    private func buildHARRequest(capture: Capture, includeHeaders: Bool, includeBodies: Bool) -> [String: Any] {
        var request: [String: Any] = [
            "method": capture.method,
            "url": capture.fullURL,
            "httpVersion": "HTTP/1.1",
            "headersSize": capture.requestHeaders?.count ?? -1,
            "bodySize": capture.requestBodySize
        ]

        request["headers"] = parseHARHeaders(from: capture.requestHeaders, includeHeaders: includeHeaders)
        request["queryString"] = parseQueryString(capture.query)
        request["cookies"] = []

        if includeBodies, let requestBody = capture.requestBody,
           let bodyString = String(data: requestBody, encoding: .utf8) {
            request["postData"] = ["mimeType": "application/json", "text": bodyString]
        }

        return request
    }

    private func buildHARResponse(capture: Capture, includeHeaders: Bool, includeBodies: Bool) -> [String: Any] {
        var response: [String: Any] = [
            "status": capture.statusCode ?? 0,
            "statusText": capture.statusMessage ?? "",
            "httpVersion": "HTTP/1.1",
            "headersSize": capture.responseHeaders?.count ?? -1,
            "bodySize": capture.responseBodySize
        ]

        response["headers"] = parseHARHeaders(from: capture.responseHeaders, includeHeaders: includeHeaders)
        response["cookies"] = []
        response["redirectURL"] = ""

        var content: [String: Any] = [
            "size": capture.responseBodySize,
            "mimeType": capture.contentType ?? "application/octet-stream"
        ]
        if includeBodies, let responseBody = capture.responseBody,
           let bodyString = String(data: responseBody, encoding: .utf8) {
            content["text"] = bodyString
        }
        response["content"] = content

        return response
    }

    private func parseHARHeaders(from headersJson: String?, includeHeaders: Bool) -> [[String: String]] {
        guard includeHeaders, let headersJson = headersJson,
              let headersDict = try? JSONSerialization.jsonObject(
                with: Data(headersJson.utf8)
              ) as? [String: String] else {
            return []
        }
        return headersDict.map { ["name": $0.key, "value": $0.value] }
    }

    // MARK: - Helpers

    private func fetchCaptures(includeFiltered: Bool) throws -> [Capture] {
        guard let db = DatabaseManager.shared.database else {
            throw ExportError.databaseNotAvailable
        }

        // includeFiltered no longer branches: filtered traffic is never persisted, so nothing to exclude.
        return try db.read { db in
            try Capture
                .order(Column("timestamp").desc)
                .fetchAll(db)
        }
    }

    private func parseQueryString(_ query: String?) -> [[String: String]] {
        guard let query = query, !query.isEmpty else { return [] }

        return query.split(separator: "&").compactMap { pair in
            let parts = pair.split(separator: "=", maxSplits: 1)
            guard parts.count >= 1 else { return nil }
            let name = String(parts[0])
            let value = parts.count > 1 ? String(parts[1]) : ""
            return ["name": name, "value": value]
        }
    }
}

// MARK: - Export Errors

enum ExportError: Error, LocalizedError {
    case databaseNotAvailable
    case fileWriteFailed(String)
    case invalidFormat

    var errorDescription: String? {
        switch self {
        case .databaseNotAvailable:
            return "Database is not available for export"
        case .fileWriteFailed(let path):
            return "Failed to write export file: \(path)"
        case .invalidFormat:
            return "Invalid export format"
        }
    }
}

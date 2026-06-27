//
//  Capture.swift
//  api-ghost
//
//  Created for APIGhost project
//

import Foundation
@preconcurrency import GRDB

/// Traffic type classification for captures.
enum TrafficType: String, Codable, Sendable {
    case http
    case streaming
    case beacon
}

/// Represents a captured HTTP request/response pair.
/// Conforms to GRDB protocols for database persistence.
struct Capture: Codable, Sendable {
    // MARK: - Properties

    /// Auto-incremented database primary key
    var id: Int64?

    /// Unique identifier for cross-referencing
    let uuid: String

    /// Timestamp when the request was captured
    let timestamp: Date

    /// Session identifier for grouping related captures
    var sessionId: String?

    // MARK: - Request Data

    /// HTTP method (GET, POST, PUT, DELETE, etc.)
    let method: String

    /// URL scheme (http, https)
    let scheme: String

    /// Target host/domain
    let host: String

    /// Port number (nil for default ports)
    var port: Int?

    /// Request path
    let path: String

    /// Query string
    var query: String?

    /// Request headers as JSON string
    var requestHeaders: String?

    /// Request body data
    var requestBody: Data?

    /// Size of request body in bytes
    var requestBodySize: Int

    // MARK: - Response Data

    /// HTTP status code
    var statusCode: Int?

    /// HTTP status message
    var statusMessage: String?

    /// Response headers as JSON string
    var responseHeaders: String?

    /// Response body data
    var responseBody: Data?

    /// Size of response body in bytes
    var responseBodySize: Int

    /// Content-Type of the response
    var contentType: String?

    // MARK: - Timing

    /// Request duration in milliseconds
    var durationMs: Int?

    // MARK: - GraphQL Metadata

    /// GraphQL operation name, when the request is a GraphQL document
    var graphqlOperationName: String?

    /// GraphQL operation type (query, mutation, subscription)
    var graphqlOperationType: String?

    // MARK: - Tab Attribution

    /// Identifier of the browser tab that produced this capture (populated later)
    var sourceTabId: String?

    // MARK: - Streaming Metadata (v2 schema)

    /// Traffic type classification (http, streaming, beacon)
    var trafficType: TrafficType

    /// Whether this was a streaming response
    var isStreaming: Bool

    /// Total number of chunks for streaming responses
    var totalChunks: Int?

    /// Total bytes transferred for streaming responses
    var totalBytes: Int?

    // MARK: - Initialization

    init(
        id: Int64? = nil,
        uuid: String = UUID().uuidString,
        timestamp: Date = Date(),
        sessionId: String? = nil,
        method: String,
        scheme: String,
        host: String,
        port: Int? = nil,
        path: String,
        query: String? = nil,
        requestHeaders: String? = nil,
        requestBody: Data? = nil,
        requestBodySize: Int = 0,
        statusCode: Int? = nil,
        statusMessage: String? = nil,
        responseHeaders: String? = nil,
        responseBody: Data? = nil,
        responseBodySize: Int = 0,
        contentType: String? = nil,
        durationMs: Int? = nil,
        graphqlOperationName: String? = nil,
        graphqlOperationType: String? = nil,
        sourceTabId: String? = nil,
        trafficType: TrafficType = .http,
        isStreaming: Bool = false,
        totalChunks: Int? = nil,
        totalBytes: Int? = nil
    ) {
        self.id = id
        self.uuid = uuid
        self.timestamp = timestamp
        self.sessionId = sessionId
        self.method = method
        self.scheme = scheme
        self.host = host
        self.port = port
        self.path = path
        self.query = query
        self.requestHeaders = requestHeaders
        self.requestBody = requestBody
        self.requestBodySize = requestBodySize
        self.statusCode = statusCode
        self.statusMessage = statusMessage
        self.responseHeaders = responseHeaders
        self.responseBody = responseBody
        self.responseBodySize = responseBodySize
        self.contentType = contentType
        self.durationMs = durationMs
        self.graphqlOperationName = graphqlOperationName
        self.graphqlOperationType = graphqlOperationType
        self.sourceTabId = sourceTabId
        self.trafficType = trafficType
        self.isStreaming = isStreaming
        self.totalChunks = totalChunks
        self.totalBytes = totalBytes
    }
}

// MARK: - GRDB Protocols

extension Capture: FetchableRecord, PersistableRecord {
    /// Database table name
    static let databaseTableName = "captures"

    /// Column to row key mapping
    enum Columns {
        static let id = Column(CodingKeys.id)
        static let uuid = Column(CodingKeys.uuid)
        static let timestamp = Column(CodingKeys.timestamp)
        static let sessionId = Column(CodingKeys.sessionId)
        static let method = Column(CodingKeys.method)
        static let scheme = Column(CodingKeys.scheme)
        static let host = Column(CodingKeys.host)
        static let port = Column(CodingKeys.port)
        static let path = Column(CodingKeys.path)
        static let query = Column(CodingKeys.query)
        static let requestHeaders = Column(CodingKeys.requestHeaders)
        static let requestBody = Column(CodingKeys.requestBody)
        static let requestBodySize = Column(CodingKeys.requestBodySize)
        static let statusCode = Column(CodingKeys.statusCode)
        static let statusMessage = Column(CodingKeys.statusMessage)
        static let responseHeaders = Column(CodingKeys.responseHeaders)
        static let responseBody = Column(CodingKeys.responseBody)
        static let responseBodySize = Column(CodingKeys.responseBodySize)
        static let contentType = Column(CodingKeys.contentType)
        static let durationMs = Column(CodingKeys.durationMs)
        static let graphqlOperationName = Column(CodingKeys.graphqlOperationName)
        static let graphqlOperationType = Column(CodingKeys.graphqlOperationType)
        static let sourceTabId = Column(CodingKeys.sourceTabId)
        static let trafficType = Column(CodingKeys.trafficType)
        static let isStreaming = Column(CodingKeys.isStreaming)
        static let totalChunks = Column(CodingKeys.totalChunks)
        static let totalBytes = Column(CodingKeys.totalBytes)
    }

    /// Custom column names to match database schema (snake_case)
    enum CodingKeys: String, CodingKey {
        case id
        case uuid
        case timestamp
        case sessionId = "session_id"
        case method
        case scheme
        case host
        case port
        case path
        case query
        case requestHeaders = "request_headers"
        case requestBody = "request_body"
        case requestBodySize = "request_body_size"
        case statusCode = "status_code"
        case statusMessage = "status_message"
        case responseHeaders = "response_headers"
        case responseBody = "response_body"
        case responseBodySize = "response_body_size"
        case contentType = "content_type"
        case durationMs = "duration_ms"
        case graphqlOperationName = "graphql_operation_name"
        case graphqlOperationType = "graphql_operation_type"
        case sourceTabId = "source_tab_id"
        case trafficType = "traffic_type"
        case isStreaming = "is_streaming"
        case totalChunks = "total_chunks"
        case totalBytes = "total_bytes"
    }

    /// Custom encoding to handle TrafficType enum
    func encode(to container: inout PersistenceContainer) throws {
        container["id"] = id
        container["uuid"] = uuid
        container["timestamp"] = timestamp
        container["session_id"] = sessionId
        container["method"] = method
        container["scheme"] = scheme
        container["host"] = host
        container["port"] = port
        container["path"] = path
        container["query"] = query
        container["request_headers"] = requestHeaders
        container["request_body"] = requestBody
        container["request_body_size"] = requestBodySize
        container["status_code"] = statusCode
        container["status_message"] = statusMessage
        container["response_headers"] = responseHeaders
        container["response_body"] = responseBody
        container["response_body_size"] = responseBodySize
        container["content_type"] = contentType
        container["duration_ms"] = durationMs
        container["graphql_operation_name"] = graphqlOperationName
        container["graphql_operation_type"] = graphqlOperationType
        container["source_tab_id"] = sourceTabId
        container["traffic_type"] = trafficType.rawValue
        container["is_streaming"] = isStreaming
        container["total_chunks"] = totalChunks
        container["total_bytes"] = totalBytes
    }

    /// Custom decoding to handle TrafficType enum and optional v2 fields
    init(row: Row) throws {
        id = row["id"]
        uuid = row["uuid"]
        timestamp = row["timestamp"]
        sessionId = row["session_id"]
        method = row["method"]
        scheme = row["scheme"]
        host = row["host"]
        port = row["port"]
        path = row["path"]
        query = row["query"]
        requestHeaders = row["request_headers"]
        requestBody = row["request_body"]
        requestBodySize = row["request_body_size"] ?? 0
        statusCode = row["status_code"]
        statusMessage = row["status_message"]
        responseHeaders = row["response_headers"]
        responseBody = row["response_body"]
        responseBodySize = row["response_body_size"] ?? 0
        contentType = row["content_type"]
        durationMs = row["duration_ms"]
        graphqlOperationName = row["graphql_operation_name"]
        graphqlOperationType = row["graphql_operation_type"]
        sourceTabId = row["source_tab_id"]

        // Handle v2 fields with defaults for older databases
        if let typeStr: String = row["traffic_type"] {
            trafficType = TrafficType(rawValue: typeStr) ?? .http
        } else {
            trafficType = .http
        }
        isStreaming = row["is_streaming"] ?? false
        totalChunks = row["total_chunks"]
        totalBytes = row["total_bytes"]
    }
}

// MARK: - Identifiable

extension Capture: Identifiable {
    // id property is already defined as Int64? which conforms to Identifiable
    // For SwiftUI lists, we can use uuid as a stable identifier when id is nil
}

// MARK: - Computed Properties

extension Capture {
    /// Returns the full URL string for this capture
    var fullURL: String {
        var url = "\(scheme)://\(host)"
        if let port = port {
            url += ":\(port)"
        }
        url += path
        if let query = query, !query.isEmpty {
            url += "?\(query)"
        }
        return url
    }

    /// Returns the decoded request headers as a dictionary
    var requestHeadersDictionary: [String: String]? {
        guard let data = requestHeaders?.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode([String: String].self, from: data)
    }

    /// Returns the decoded response headers as a dictionary
    var responseHeadersDictionary: [String: String]? {
        guard let data = responseHeaders?.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode([String: String].self, from: data)
    }

    /// Returns the status code category (2xx, 3xx, 4xx, 5xx)
    var statusCategory: String? {
        guard let code = statusCode else { return nil }
        switch code {
        case 100..<200: return "1xx"
        case 200..<300: return "2xx"
        case 300..<400: return "3xx"
        case 400..<500: return "4xx"
        case 500..<600: return "5xx"
        default: return "unknown"
        }
    }

    /// Returns a human-readable traffic type label
    var trafficTypeLabel: String {
        switch trafficType {
        case .http:
            return isStreaming ? "HTTP (Streaming)" : "HTTP"
        case .streaming:
            return "Streaming"
        case .beacon:
            return "Beacon"
        }
    }

    /// Returns whether this capture has associated stream chunks
    var hasStreamChunks: Bool {
        isStreaming && (totalChunks ?? 0) > 0
    }
}

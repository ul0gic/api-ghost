//
//  RealtimeConnection.swift
//  api-ghost
//
//  Created for APIGhost project
//  Represents a WebSocket or SSE connection for real-time traffic capture.
//

import Foundation
import GRDB

/// The type of real-time connection.
enum ConnectionType: String, Codable, Sendable {
    case websocket
    case sse
}

/// The current status of a real-time connection.
enum ConnectionStatus: String, Codable, Sendable {
    case connecting
    case open
    case closing
    case closed
    case error
}

/// Represents a WebSocket or Server-Sent Events (SSE) connection.
/// Tracks the lifecycle and statistics of real-time connections.
struct RealtimeConnection: Codable, Sendable {
    // MARK: - Properties

    /// Auto-incremented database primary key
    var id: Int64?

    /// Unique connection identifier from JavaScript interceptor
    let connectionId: String

    /// Session identifier for grouping related connections
    var sessionId: String?

    /// Type of connection (websocket or sse)
    let connectionType: ConnectionType

    /// Full URL of the connection
    let url: String

    /// Host extracted from URL
    let host: String

    /// Path extracted from URL
    let path: String

    /// WebSocket protocol (if applicable)
    var websocketProtocol: String?

    /// WebSocket extensions (if applicable)
    var extensions: String?

    /// SSE withCredentials flag
    var withCredentials: Bool

    /// Timestamp when connection was opened
    let openedAt: Date

    /// Timestamp when connection was closed (nil if still open)
    var closedAt: Date?

    /// Duration in milliseconds (set when closed)
    var durationMs: Int?

    /// Current connection status
    var status: ConnectionStatus

    /// WebSocket close code
    var closeCode: Int?

    /// WebSocket close reason
    var closeReason: String?

    /// Whether WebSocket closed cleanly
    var wasClean: Bool?

    /// Count of messages sent
    var messagesSent: Int

    /// Count of messages received
    var messagesReceived: Int

    /// Total bytes sent
    var bytesSent: Int

    /// Total bytes received
    var bytesReceived: Int

    // MARK: - Initialization

    init(
        id: Int64? = nil,
        connectionId: String,
        sessionId: String? = nil,
        connectionType: ConnectionType,
        url: String,
        host: String,
        path: String,
        websocketProtocol: String? = nil,
        extensions: String? = nil,
        withCredentials: Bool = false,
        openedAt: Date = Date(),
        closedAt: Date? = nil,
        durationMs: Int? = nil,
        status: ConnectionStatus = .connecting,
        closeCode: Int? = nil,
        closeReason: String? = nil,
        wasClean: Bool? = nil,
        messagesSent: Int = 0,
        messagesReceived: Int = 0,
        bytesSent: Int = 0,
        bytesReceived: Int = 0
    ) {
        self.id = id
        self.connectionId = connectionId
        self.sessionId = sessionId
        self.connectionType = connectionType
        self.url = url
        self.host = host
        self.path = path
        self.websocketProtocol = websocketProtocol
        self.extensions = extensions
        self.withCredentials = withCredentials
        self.openedAt = openedAt
        self.closedAt = closedAt
        self.durationMs = durationMs
        self.status = status
        self.closeCode = closeCode
        self.closeReason = closeReason
        self.wasClean = wasClean
        self.messagesSent = messagesSent
        self.messagesReceived = messagesReceived
        self.bytesSent = bytesSent
        self.bytesReceived = bytesReceived
    }

    /// Creates a connection from URL string, extracting host and path.
    static func create(
        connectionId: String,
        sessionId: String?,
        connectionType: ConnectionType,
        url: String,
        withCredentials: Bool = false
    ) -> RealtimeConnection {
        let components = URLComponents(string: url)
        let host = components?.host ?? ""
        let path = components?.path.isEmpty == true ? "/" : (components?.path ?? "/")

        return RealtimeConnection(
            connectionId: connectionId,
            sessionId: sessionId,
            connectionType: connectionType,
            url: url,
            host: host,
            path: path,
            withCredentials: withCredentials
        )
    }
}

// MARK: - GRDB Protocols

extension RealtimeConnection: FetchableRecord, PersistableRecord {
    /// Database table name
    static let databaseTableName = "realtime_connections"

    /// Column to row key mapping
    enum Columns {
        static let id = Column(CodingKeys.id)
        static let connectionId = Column(CodingKeys.connectionId)
        static let sessionId = Column(CodingKeys.sessionId)
        static let connectionType = Column(CodingKeys.connectionType)
        static let url = Column(CodingKeys.url)
        static let host = Column(CodingKeys.host)
        static let path = Column(CodingKeys.path)
        static let websocketProtocol = Column(CodingKeys.websocketProtocol)
        static let extensions = Column(CodingKeys.extensions)
        static let withCredentials = Column(CodingKeys.withCredentials)
        static let openedAt = Column(CodingKeys.openedAt)
        static let closedAt = Column(CodingKeys.closedAt)
        static let durationMs = Column(CodingKeys.durationMs)
        static let status = Column(CodingKeys.status)
        static let closeCode = Column(CodingKeys.closeCode)
        static let closeReason = Column(CodingKeys.closeReason)
        static let wasClean = Column(CodingKeys.wasClean)
        static let messagesSent = Column(CodingKeys.messagesSent)
        static let messagesReceived = Column(CodingKeys.messagesReceived)
        static let bytesSent = Column(CodingKeys.bytesSent)
        static let bytesReceived = Column(CodingKeys.bytesReceived)
    }

    /// Custom column names to match database schema (snake_case)
    enum CodingKeys: String, CodingKey {
        case id
        case connectionId = "connection_id"
        case sessionId = "session_id"
        case connectionType = "connection_type"
        case url
        case host
        case path
        case websocketProtocol = "protocol"
        case extensions
        case withCredentials = "with_credentials"
        case openedAt = "opened_at"
        case closedAt = "closed_at"
        case durationMs = "duration_ms"
        case status
        case closeCode = "close_code"
        case closeReason = "close_reason"
        case wasClean = "was_clean"
        case messagesSent = "messages_sent"
        case messagesReceived = "messages_received"
        case bytesSent = "bytes_sent"
        case bytesReceived = "bytes_received"
    }
}

// MARK: - Identifiable

extension RealtimeConnection: Identifiable {
    // id property is already defined
}

// MARK: - Computed Properties

extension RealtimeConnection {
    /// Returns a human-readable connection type string
    var typeDisplayName: String {
        switch connectionType {
        case .websocket:
            return "WebSocket"
        case .sse:
            return "SSE"
        }
    }

    /// Returns the total message count (sent + received)
    var totalMessages: Int {
        messagesSent + messagesReceived
    }

    /// Returns the total bytes transferred
    var totalBytes: Int {
        bytesSent + bytesReceived
    }

    /// Returns whether the connection is currently active
    var isActive: Bool {
        status == .connecting || status == .open
    }

    /// Returns a formatted duration string
    var formattedDuration: String {
        guard let ms = durationMs else { return "-" }
        if ms < 1000 {
            return "\(ms)ms"
        } else if ms < 60000 {
            return String(format: "%.1fs", Double(ms) / 1000.0)
        } else {
            let minutes = ms / 60000
            let seconds = (ms % 60000) / 1000
            return "\(minutes)m \(seconds)s"
        }
    }
}

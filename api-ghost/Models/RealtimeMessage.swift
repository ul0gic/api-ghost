//
//  RealtimeMessage.swift
//  api-ghost
//
//  Created for APIGhost project
//  Represents an individual message within a WebSocket or SSE connection.
//

import Foundation
import GRDB

/// Direction of a message in a real-time connection.
enum MessageDirection: String, Codable, Sendable {
    case send
    case receive
}

/// Type of message data.
enum MessageDataType: String, Codable, Sendable {
    case text
    case binary
}

/// Represents a single message within a WebSocket or SSE connection.
struct RealtimeMessage: Codable, Sendable {
    // MARK: - Properties

    /// Auto-incremented database primary key
    var id: Int64?

    /// Reference to parent connection
    let connectionId: String

    /// Session identifier for quick filtering
    var sessionId: String?

    /// Message direction (send/receive)
    let direction: MessageDirection

    /// Event type (message, open, close, error, or custom SSE event)
    let eventType: String

    /// Data type (text or binary)
    let dataType: MessageDataType

    /// Message content (text or base64-encoded binary)
    var data: Data?

    /// Size of data in bytes
    var dataSize: Int

    /// SSE lastEventId (if applicable)
    var lastEventId: String?

    /// Timestamp when message was captured
    let timestamp: Date

    /// Sequence number within the connection
    var sequenceNum: Int

    // MARK: - Initialization

    init(
        id: Int64? = nil,
        connectionId: String,
        sessionId: String? = nil,
        direction: MessageDirection,
        eventType: String,
        dataType: MessageDataType = .text,
        data: Data? = nil,
        dataSize: Int = 0,
        lastEventId: String? = nil,
        timestamp: Date = Date(),
        sequenceNum: Int = 0
    ) {
        self.id = id
        self.connectionId = connectionId
        self.sessionId = sessionId
        self.direction = direction
        self.eventType = eventType
        self.dataType = dataType
        self.data = data
        self.dataSize = dataSize
        self.lastEventId = lastEventId
        self.timestamp = timestamp
        self.sequenceNum = sequenceNum
    }

    /// Creates a message from string data
    static func fromText(
        connectionId: String,
        sessionId: String?,
        direction: MessageDirection,
        eventType: String,
        text: String?,
        lastEventId: String? = nil,
        sequenceNum: Int = 0
    ) -> RealtimeMessage {
        let data = text?.data(using: .utf8)
        return RealtimeMessage(
            connectionId: connectionId,
            sessionId: sessionId,
            direction: direction,
            eventType: eventType,
            dataType: .text,
            data: data,
            dataSize: data?.count ?? 0,
            lastEventId: lastEventId,
            sequenceNum: sequenceNum
        )
    }

    /// Creates a message from binary data (base64 encoded string from JS)
    static func fromBinary(
        connectionId: String,
        sessionId: String?,
        direction: MessageDirection,
        eventType: String,
        base64Data: String?,
        originalSize: Int,
        sequenceNum: Int = 0
    ) -> RealtimeMessage {
        let data = base64Data.flatMap { Data(base64Encoded: $0) }
        return RealtimeMessage(
            connectionId: connectionId,
            sessionId: sessionId,
            direction: direction,
            eventType: eventType,
            dataType: .binary,
            data: data,
            dataSize: originalSize,
            sequenceNum: sequenceNum
        )
    }
}

// MARK: - GRDB Protocols

extension RealtimeMessage: FetchableRecord, PersistableRecord {
    /// Database table name
    static let databaseTableName = "realtime_messages"

    /// Column to row key mapping
    enum Columns {
        static let id = Column(CodingKeys.id)
        static let connectionId = Column(CodingKeys.connectionId)
        static let sessionId = Column(CodingKeys.sessionId)
        static let direction = Column(CodingKeys.direction)
        static let eventType = Column(CodingKeys.eventType)
        static let dataType = Column(CodingKeys.dataType)
        static let data = Column(CodingKeys.data)
        static let dataSize = Column(CodingKeys.dataSize)
        static let lastEventId = Column(CodingKeys.lastEventId)
        static let timestamp = Column(CodingKeys.timestamp)
        static let sequenceNum = Column(CodingKeys.sequenceNum)
    }

    /// Custom column names to match database schema (snake_case)
    enum CodingKeys: String, CodingKey {
        case id
        case connectionId = "connection_id"
        case sessionId = "session_id"
        case direction
        case eventType = "event_type"
        case dataType = "data_type"
        case data
        case dataSize = "data_size"
        case lastEventId = "last_event_id"
        case timestamp
        case sequenceNum = "sequence_num"
    }
}

// MARK: - Identifiable

extension RealtimeMessage: Identifiable {
    // id property is already defined
}

// MARK: - Computed Properties

extension RealtimeMessage {
    /// Returns the data as a string (for text messages)
    var dataString: String? {
        guard let data = data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Returns a truncated preview of the data
    var dataPreview: String {
        guard let str = dataString else {
            if dataType == .binary {
                return "[Binary: \(dataSize) bytes]"
            }
            return "[No data]"
        }

        if str.count > 200 {
            return String(str.prefix(200)) + "..."
        }
        return str
    }

    /// Returns whether this is a control message (open, close, error)
    var isControlMessage: Bool {
        ["open", "close", "error", "connecting", "closing"].contains(eventType)
    }

    /// Returns a human-readable direction string
    var directionDisplayName: String {
        switch direction {
        case .send:
            return "Sent"
        case .receive:
            return "Received"
        }
    }

    /// Returns the direction arrow symbol
    var directionSymbol: String {
        switch direction {
        case .send:
            return "->"
        case .receive:
            return "<-"
        }
    }
}

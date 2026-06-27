import Foundation
import GRDB

enum MessageDirection: String, Codable, Sendable {
    case send
    case receive
}

enum MessageDataType: String, Codable, Sendable {
    case text
    case binary
}

nonisolated struct RealtimeMessage: Codable, Sendable {
    // MARK: - Properties

    var id: Int64?

    let connectionId: String

    var sessionId: String?

    let direction: MessageDirection

    let eventType: String

    let dataType: MessageDataType

    var data: Data?

    var dataSize: Int

    var lastEventId: String?

    let timestamp: Date

    var sequenceNum: Int

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

extension RealtimeMessage: nonisolated FetchableRecord { }

extension RealtimeMessage: PersistableRecord {
    nonisolated static let databaseTableName = "realtime_messages"

    nonisolated enum Columns {
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
}

// MARK: - Identifiable

extension RealtimeMessage: nonisolated Identifiable {
}

// MARK: - Computed Properties

extension RealtimeMessage {
    var dataString: String? {
        guard let data = data else { return nil }
        return String(data: data, encoding: .utf8)
    }

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

    var isControlMessage: Bool {
        ["open", "close", "error", "connecting", "closing"].contains(eventType)
    }

    var directionDisplayName: String {
        switch direction {
        case .send:
            return "Sent"
        case .receive:
            return "Received"
        }
    }

    var directionSymbol: String {
        switch direction {
        case .send:
            return "->"
        case .receive:
            return "<-"
        }
    }
}

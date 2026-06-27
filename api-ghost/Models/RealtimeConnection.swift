import Foundation
import GRDB

enum ConnectionType: String, Codable, Sendable {
    case websocket
    case sse
}

enum ConnectionStatus: String, Codable, Sendable {
    case connecting
    case open
    case closing
    case closed
    case error
}

struct RealtimeConnection: Codable, Sendable {
    // MARK: - Properties

    var id: Int64?

    let connectionId: String

    var sessionId: String?

    let connectionType: ConnectionType

    let url: String

    let host: String

    let path: String

    var websocketProtocol: String?

    var extensions: String?

    var withCredentials: Bool

    let openedAt: Date

    var closedAt: Date?

    var durationMs: Int?

    var status: ConnectionStatus

    var closeCode: Int?

    var closeReason: String?

    var wasClean: Bool?

    var messagesSent: Int

    var messagesReceived: Int

    var bytesSent: Int

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
    static let databaseTableName = "realtime_connections"

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
}

// MARK: - Computed Properties

extension RealtimeConnection {
    var typeDisplayName: String {
        switch connectionType {
        case .websocket:
            return "WebSocket"
        case .sse:
            return "SSE"
        }
    }

    var totalMessages: Int {
        messagesSent + messagesReceived
    }

    var totalBytes: Int {
        bytesSent + bytesReceived
    }

    var isActive: Bool {
        status == .connecting || status == .open
    }

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

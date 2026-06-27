import Foundation
import GRDB

struct RealtimeDeletionResult {
    let connections: Int
    let messages: Int
    let chunks: Int
}

final class RealtimeStore: Sendable {
    // MARK: - Singleton

    static let shared = RealtimeStore()

    // MARK: - Properties

    private var database: DatabaseQueue? {
        DatabaseManager.shared.database
    }

    // MARK: - Initialization

    private init() {}

    // MARK: - Connection Operations

    @discardableResult
    func saveConnection(_ connection: RealtimeConnection) throws -> RealtimeConnection {
        guard let db = database else {
            throw DatabaseError.notInitialized
        }
        return try db.write { db in
            try connection.inserted(db)
        }
    }

    func updateConnectionStatus(
        connectionId: String,
        status: ConnectionStatus,
        wsProtocol: String? = nil,
        extensions: String? = nil
    ) throws {
        guard let db = database else {
            throw DatabaseError.notInitialized
        }
        try db.write { db in
            try db.execute(
                sql: """
                    UPDATE realtime_connections
                    SET status = ?, protocol = COALESCE(?, protocol), extensions = COALESCE(?, extensions)
                    WHERE connection_id = ?
                """,
                arguments: [status.rawValue, wsProtocol, extensions, connectionId]
            )
        }
    }

    func closeConnection(
        connectionId: String,
        status: ConnectionStatus,
        closeCode: Int? = nil,
        closeReason: String? = nil,
        wasClean: Bool? = nil,
        durationMs: Int? = nil,
        messagesSent: Int? = nil,
        messagesReceived: Int? = nil
    ) throws {
        guard let db = database else {
            throw DatabaseError.notInitialized
        }
        try db.write { db in
            try db.execute(
                sql: """
                    UPDATE realtime_connections
                    SET status = ?,
                        closed_at = CURRENT_TIMESTAMP,
                        close_code = COALESCE(?, close_code),
                        close_reason = COALESCE(?, close_reason),
                        was_clean = COALESCE(?, was_clean),
                        duration_ms = COALESCE(?, duration_ms),
                        messages_sent = COALESCE(?, messages_sent),
                        messages_received = COALESCE(?, messages_received)
                    WHERE connection_id = ?
                """,
                arguments: [
                    status.rawValue,
                    closeCode,
                    closeReason,
                    wasClean,
                    durationMs,
                    messagesSent,
                    messagesReceived,
                    connectionId
                ]
            )
        }
    }

    func fetchConnection(byId connectionId: String) throws -> RealtimeConnection? {
        guard let db = database else { return nil }
        return try db.read { db in
            try RealtimeConnection
                .filter(Column("connection_id") == connectionId)
                .fetchOne(db)
        }
    }

    func fetchConnections(
        type: ConnectionType? = nil,
        limit: Int = 100
    ) throws -> [RealtimeConnection] {
        guard let db = database else { return [] }
        return try db.read { db in
            var request = RealtimeConnection.order(Column("opened_at").desc)

            if let type = type {
                request = request.filter(Column("connection_type") == type.rawValue)
            }

            return try request.limit(limit).fetchAll(db)
        }
    }

    func fetchActiveConnections() throws -> [RealtimeConnection] {
        guard let db = database else { return [] }
        return try db.read { db in
            try RealtimeConnection
                .filter(Column("status") == ConnectionStatus.open.rawValue ||
                        Column("status") == ConnectionStatus.connecting.rawValue)
                .order(Column("opened_at").desc)
                .fetchAll(db)
        }
    }

    func connectionCount(type: ConnectionType? = nil) throws -> Int {
        guard let db = database else { return 0 }
        return try db.read { db in
            var request = RealtimeConnection.all()
            if let type = type {
                request = request.filter(Column("connection_type") == type.rawValue)
            }
            return try request.fetchCount(db)
        }
    }

    // MARK: - Message Operations

    @discardableResult
    func saveMessage(_ message: RealtimeMessage) throws -> RealtimeMessage {
        guard let db = database else {
            throw DatabaseError.notInitialized
        }
        return try db.write { db in
            try message.inserted(db)
        }
    }

    @discardableResult
    func saveMessages(_ messages: [RealtimeMessage]) throws -> [RealtimeMessage] {
        guard let db = database else {
            throw DatabaseError.notInitialized
        }
        return try db.write { db in
            try messages.map { try $0.inserted(db) }
        }
    }

    func fetchMessages(
        forConnection connectionId: String,
        limit: Int = 500,
        offset: Int = 0
    ) throws -> [RealtimeMessage] {
        guard let db = database else { return [] }
        return try db.read { db in
            try RealtimeMessage
                .filter(Column("connection_id") == connectionId)
                .order(Column("sequence_num").asc)
                .limit(limit, offset: offset)
                .fetchAll(db)
        }
    }

    func messageCount(forConnection connectionId: String) throws -> Int {
        guard let db = database else { return 0 }
        return try db.read { db in
            try RealtimeMessage
                .filter(Column("connection_id") == connectionId)
                .fetchCount(db)
        }
    }

    func fetchRecentMessages(limit: Int = 100) throws -> [RealtimeMessage] {
        guard let db = database else { return [] }
        return try db.read { db in
            try RealtimeMessage
                .order(Column("timestamp").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    func searchMessages(
        containing searchText: String,
        connectionId: String? = nil,
        limit: Int = 100
    ) throws -> [RealtimeMessage] {
        guard let db = database else { return [] }
        return try db.read { db in
            var request = RealtimeMessage
                .filter(Column("data").like("%\(searchText)%"))
                .order(Column("timestamp").desc)

            if let connectionId = connectionId {
                request = request.filter(Column("connection_id") == connectionId)
            }

            return try request.limit(limit).fetchAll(db)
        }
    }

    // MARK: - Stream Chunk Operations

    @discardableResult
    func saveStreamChunk(_ chunk: StreamChunk) throws -> StreamChunk {
        guard let db = database else {
            throw DatabaseError.notInitialized
        }
        return try db.write { db in
            try chunk.inserted(db)
        }
    }

    func fetchChunks(forCapture captureUUID: String) throws -> [StreamChunk] {
        guard let db = database else { return [] }
        return try db.read { db in
            try StreamChunk
                .filter(Column("capture_uuid") == captureUUID)
                .order(Column("chunk_index").asc)
                .fetchAll(db)
        }
    }

    func reconstructStreamBody(forCapture captureUUID: String) throws -> Data? {
        let chunks = try fetchChunks(forCapture: captureUUID)
        guard !chunks.isEmpty else { return nil }

        var combined = Data()
        for chunk in chunks {
            if let data = chunk.data {
                combined.append(data)
            }
        }
        return combined
    }

    func chunkCount(forCapture captureUUID: String) throws -> Int {
        guard let db = database else { return 0 }
        return try db.read { db in
            try StreamChunk
                .filter(Column("capture_uuid") == captureUUID)
                .fetchCount(db)
        }
    }
}

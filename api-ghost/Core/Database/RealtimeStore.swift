//
//  RealtimeStore.swift
//  api-ghost
//
//  Created for APIGhost project
//  Provides CRUD operations for real-time traffic (WebSocket, SSE, streaming).
//

import Foundation
import GRDB

/// Counts of deleted realtime data items.
struct RealtimeDeletionResult {
    let connections: Int
    let messages: Int
    let chunks: Int
}

/// Provides CRUD operations for real-time traffic records in the database.
/// Thread-safe singleton for managing WebSocket, SSE connections and messages.
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

    /// Saves a new real-time connection to the database.
    /// - Parameter connection: The connection to save
    /// - Returns: The saved connection with its assigned database ID
    /// - Throws: Database errors if the save fails
    @discardableResult
    func saveConnection(_ connection: RealtimeConnection) throws -> RealtimeConnection {
        guard let db = database else {
            throw DatabaseError.notInitialized
        }
        return try db.write { db in
            try connection.inserted(db)
        }
    }

    /// Updates a connection's status.
    /// - Parameters:
    ///   - connectionId: The connection ID to update
    ///   - status: The new status
    ///   - wsProtocol: WebSocket protocol (optional)
    ///   - extensions: WebSocket extensions (optional)
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

    /// Closes a connection and updates its final statistics.
    /// - Parameters:
    ///   - connectionId: The connection ID to close
    ///   - status: The final status (closed or error)
    ///   - closeCode: WebSocket close code (optional)
    ///   - closeReason: WebSocket close reason (optional)
    ///   - wasClean: Whether WebSocket closed cleanly (optional)
    ///   - durationMs: Connection duration in milliseconds (optional)
    ///   - messagesSent: Final count of sent messages (optional)
    ///   - messagesReceived: Final count of received messages (optional)
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

    /// Fetches a connection by its ID.
    /// - Parameter connectionId: The connection ID to fetch
    /// - Returns: The connection if found, nil otherwise
    func fetchConnection(byId connectionId: String) throws -> RealtimeConnection? {
        guard let db = database else { return nil }
        return try db.read { db in
            try RealtimeConnection
                .filter(Column("connection_id") == connectionId)
                .fetchOne(db)
        }
    }

    /// Fetches all connections, optionally filtered by type.
    /// - Parameters:
    ///   - type: Connection type filter (optional)
    ///   - limit: Maximum number of connections to return
    /// - Returns: Array of connections
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

    /// Fetches active (non-closed) connections.
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

    /// Returns the count of connections by type.
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

    /// Saves a real-time message to the database.
    /// - Parameter message: The message to save
    /// - Returns: The saved message with its assigned database ID
    @discardableResult
    func saveMessage(_ message: RealtimeMessage) throws -> RealtimeMessage {
        guard let db = database else {
            throw DatabaseError.notInitialized
        }
        return try db.write { db in
            try message.inserted(db)
        }
    }

    /// Saves multiple messages in a batch.
    /// - Parameter messages: The messages to save
    @discardableResult
    func saveMessages(_ messages: [RealtimeMessage]) throws -> [RealtimeMessage] {
        guard let db = database else {
            throw DatabaseError.notInitialized
        }
        return try db.write { db in
            try messages.map { try $0.inserted(db) }
        }
    }

    /// Fetches messages for a specific connection.
    /// - Parameters:
    ///   - connectionId: The connection ID to fetch messages for
    ///   - limit: Maximum number of messages to return
    ///   - offset: Number of messages to skip
    /// - Returns: Array of messages ordered by sequence number
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

    /// Returns the count of messages for a connection.
    func messageCount(forConnection connectionId: String) throws -> Int {
        guard let db = database else { return 0 }
        return try db.read { db in
            try RealtimeMessage
                .filter(Column("connection_id") == connectionId)
                .fetchCount(db)
        }
    }

    /// Fetches recent messages across all connections.
    /// - Parameter limit: Maximum number of messages to return
    /// - Returns: Array of recent messages
    func fetchRecentMessages(limit: Int = 100) throws -> [RealtimeMessage] {
        guard let db = database else { return [] }
        return try db.read { db in
            try RealtimeMessage
                .order(Column("timestamp").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    /// Searches messages containing the specified text.
    /// - Parameters:
    ///   - searchText: Text to search for
    ///   - connectionId: Optional connection ID filter
    ///   - limit: Maximum results
    /// - Returns: Array of matching messages
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

    /// Saves a stream chunk to the database.
    /// - Parameter chunk: The chunk to save
    /// - Returns: The saved chunk with its assigned database ID
    @discardableResult
    func saveStreamChunk(_ chunk: StreamChunk) throws -> StreamChunk {
        guard let db = database else {
            throw DatabaseError.notInitialized
        }
        return try db.write { db in
            try chunk.inserted(db)
        }
    }

    /// Fetches all chunks for a capture.
    /// - Parameter captureUUID: The capture UUID to fetch chunks for
    /// - Returns: Array of chunks ordered by index
    func fetchChunks(forCapture captureUUID: String) throws -> [StreamChunk] {
        guard let db = database else { return [] }
        return try db.read { db in
            try StreamChunk
                .filter(Column("capture_uuid") == captureUUID)
                .order(Column("chunk_index").asc)
                .fetchAll(db)
        }
    }

    /// Reconstructs the full response body from chunks.
    /// - Parameter captureUUID: The capture UUID
    /// - Returns: The combined data from all chunks
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

    /// Returns the count of chunks for a capture.
    func chunkCount(forCapture captureUUID: String) throws -> Int {
        guard let db = database else { return 0 }
        return try db.read { db in
            try StreamChunk
                .filter(Column("capture_uuid") == captureUUID)
                .fetchCount(db)
        }
    }

    // Cleanup operations, statistics, and RealtimeStatistics are in RealtimeStore+Operations.swift
}

//
//  RealtimeStore+Operations.swift
//  APIGhost
//
//  Cleanup operations and statistics for RealtimeStore.
//

import Foundation
import GRDB

// MARK: - Cleanup Operations

extension RealtimeStore {
    /// Deletes all real-time data (connections, messages, chunks).
    func deleteAll() throws {
        guard let db = DatabaseManager.shared.database else {
            throw DatabaseError.notInitialized
        }
        try db.write { db in
            _ = try RealtimeConnection.deleteAll(db)
            _ = try StreamChunk.deleteAll(db)
        }
    }

    /// Deletes data older than the specified date.
    /// - Parameter date: Delete data older than this date
    /// - Returns: Count of deleted items
    @discardableResult
    func deleteOlderThan(_ date: Date) throws -> RealtimeDeletionResult {
        guard let db = DatabaseManager.shared.database else {
            throw DatabaseError.notInitialized
        }
        return try db.write { db in
            let messagesDeleted = try RealtimeMessage
                .filter(Column("timestamp") < date)
                .deleteAll(db)

            let connectionsDeleted = try RealtimeConnection
                .filter(Column("opened_at") < date)
                .deleteAll(db)

            let chunksDeleted = try StreamChunk
                .filter(Column("timestamp") < date)
                .deleteAll(db)

            return RealtimeDeletionResult(
                connections: connectionsDeleted,
                messages: messagesDeleted,
                chunks: chunksDeleted
            )
        }
    }

    /// Deletes all data for a specific session.
    /// - Parameter sessionId: The session ID to delete
    func deleteSession(_ sessionId: String) throws {
        guard let db = DatabaseManager.shared.database else {
            throw DatabaseError.notInitialized
        }
        try db.write { db in
            _ = try RealtimeMessage
                .filter(Column("session_id") == sessionId)
                .deleteAll(db)

            _ = try RealtimeConnection
                .filter(Column("session_id") == sessionId)
                .deleteAll(db)

            _ = try StreamChunk
                .filter(Column("session_id") == sessionId)
                .deleteAll(db)
        }
    }

    // MARK: - Statistics

    /// Returns aggregate statistics for real-time traffic.
    func getStatistics() throws -> RealtimeStatistics {
        guard let db = DatabaseManager.shared.database else {
            return RealtimeStatistics()
        }
        return try db.read { db in
            let wsCount = try RealtimeConnection
                .filter(Column("connection_type") == ConnectionType.websocket.rawValue)
                .fetchCount(db)

            let sseCount = try RealtimeConnection
                .filter(Column("connection_type") == ConnectionType.sse.rawValue)
                .fetchCount(db)

            let messageCount = try RealtimeMessage.fetchCount(db)
            let chunkCount = try StreamChunk.fetchCount(db)

            let rows = try Row.fetchAll(db, sql: """
                SELECT
                    COALESCE(SUM(bytes_sent), 0) as bytes_sent,
                    COALESCE(SUM(bytes_received), 0) as bytes_received
                FROM realtime_connections
            """)

            let bytesSent = rows.first?["bytes_sent"] as? Int ?? 0
            let bytesReceived = rows.first?["bytes_received"] as? Int ?? 0

            return RealtimeStatistics(
                websocketConnections: wsCount,
                sseConnections: sseCount,
                totalMessages: messageCount,
                streamChunks: chunkCount,
                bytesSent: bytesSent,
                bytesReceived: bytesReceived
            )
        }
    }
}

// MARK: - Statistics Model

/// Aggregate statistics for real-time traffic.
struct RealtimeStatistics {
    var websocketConnections: Int = 0
    var sseConnections: Int = 0
    var totalMessages: Int = 0
    var streamChunks: Int = 0
    var bytesSent: Int = 0
    var bytesReceived: Int = 0

    var totalConnections: Int {
        websocketConnections + sseConnections
    }

    var totalBytes: Int {
        bytesSent + bytesReceived
    }
}

//
//  Migrations.swift
//  api-ghost
//
//  Created for APIGhost project
//

import Foundation
import GRDB

/// Handles database schema migrations for APIGhost.
/// All schema changes should be registered here as versioned migrations.
struct Migrations {
    /// Registers all database migrations with the migrator.
    static func registerMigrations(_ migrator: inout DatabaseMigrator) {
        registerV1Migration(&migrator)
        registerV2Migration(&migrator)
        registerV3Migration(&migrator)
    }

    /// v1: Initial schema - captures table
    private static func registerV1Migration(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v1_initial") { db in
            // Create captures table for storing HTTP request/response data
            try db.create(table: "captures") { table in
                // Primary key
                table.autoIncrementedPrimaryKey("id")

                // Unique identifier for cross-referencing
                table.column("uuid", .text).notNull().unique()

                // Timestamp of capture
                table.column("timestamp", .datetime).notNull()

                // Session identifier for grouping related captures
                table.column("session_id", .text)

                // Request data
                table.column("method", .text).notNull()
                table.column("scheme", .text).notNull()
                table.column("host", .text).notNull()
                table.column("port", .integer)
                table.column("path", .text).notNull()
                table.column("query", .text)
                table.column("request_headers", .text) // JSON encoded
                table.column("request_body", .blob)
                table.column("request_body_size", .integer).notNull().defaults(to: 0)

                // Response data
                table.column("status_code", .integer)
                table.column("status_message", .text)
                table.column("response_headers", .text) // JSON encoded
                table.column("response_body", .blob)
                table.column("response_body_size", .integer).notNull().defaults(to: 0)
                table.column("content_type", .text)

                // Timing
                table.column("duration_ms", .integer)

                // Filter metadata
                table.column("was_filtered", .boolean).notNull().defaults(to: false)
                table.column("filter_reason", .text)
            }

            // Create indexes for common query patterns
            try db.create(index: "idx_captures_host", on: "captures", columns: ["host"])
            try db.create(index: "idx_captures_timestamp", on: "captures", columns: ["timestamp"])
            try db.create(index: "idx_captures_path", on: "captures", columns: ["path"])
            try db.create(index: "idx_captures_session_id", on: "captures", columns: ["session_id"])
            try db.create(index: "idx_captures_method", on: "captures", columns: ["method"])
            try db.create(index: "idx_captures_status_code", on: "captures", columns: ["status_code"])
        }
    }

    /// v2: Add real-time traffic tables for WebSocket, SSE, and streaming data
    private static func registerV2Migration(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v2_realtime_traffic") { db in
            try createRealtimeConnectionsTable(db)
            try createRealtimeMessagesTable(db)
            try createStreamChunksTable(db)
            try addRealtimeColumnsToCaptures(db)
        }
    }

    private static func createRealtimeConnectionsTable(_ db: Database) throws {
        try db.create(table: "realtime_connections") { table in
                // Primary key
                table.autoIncrementedPrimaryKey("id")

                // Unique connection identifier (from JavaScript)
                table.column("connection_id", .text).notNull().unique()

                // Session identifier for grouping
                table.column("session_id", .text)

                // Connection type: 'websocket' or 'sse'
                table.column("connection_type", .text).notNull()

                // URL of the connection
                table.column("url", .text).notNull()

                // Host extracted from URL for filtering/grouping
                table.column("host", .text).notNull()

                // Path extracted from URL
                table.column("path", .text).notNull()

                // For WebSocket: protocol and extensions
                table.column("protocol", .text)
                table.column("extensions", .text)

                // For SSE: withCredentials flag
                table.column("with_credentials", .boolean).notNull().defaults(to: false)

                // Connection timestamps
                table.column("opened_at", .datetime).notNull()
                table.column("closed_at", .datetime)

                // Duration in milliseconds (set when closed)
                table.column("duration_ms", .integer)

                // Connection status: 'connecting', 'open', 'closing', 'closed', 'error'
                table.column("status", .text).notNull().defaults(to: "connecting")

                // Close reason (for WebSocket)
                table.column("close_code", .integer)
                table.column("close_reason", .text)
                table.column("was_clean", .boolean)

                // Message counts
                table.column("messages_sent", .integer).notNull().defaults(to: 0)
                table.column("messages_received", .integer).notNull().defaults(to: 0)

                // Total bytes transferred
                table.column("bytes_sent", .integer).notNull().defaults(to: 0)
                table.column("bytes_received", .integer).notNull().defaults(to: 0)
        }

        try db.create(index: "idx_realtime_conn_id", on: "realtime_connections", columns: ["connection_id"])
        try db.create(index: "idx_realtime_conn_type", on: "realtime_connections", columns: ["connection_type"])
        try db.create(index: "idx_realtime_conn_host", on: "realtime_connections", columns: ["host"])
        try db.create(index: "idx_realtime_conn_session", on: "realtime_connections", columns: ["session_id"])
        try db.create(index: "idx_realtime_conn_opened", on: "realtime_connections", columns: ["opened_at"])
    }

    private static func createRealtimeMessagesTable(_ db: Database) throws {
        try db.create(table: "realtime_messages") { table in
                // Primary key
                table.autoIncrementedPrimaryKey("id")

                // Reference to parent connection
                table.column("connection_id", .text)
                    .notNull()
                    .references("realtime_connections", column: "connection_id", onDelete: .cascade)

                // Session identifier for quick filtering
                table.column("session_id", .text)

                // Message direction: 'send' or 'receive' (for WebSocket)
                // For SSE, this is always 'receive'
                table.column("direction", .text).notNull()

                // Event type: 'message', 'open', 'close', 'error', or custom SSE event name
                table.column("event_type", .text).notNull()

                // Message data type: 'text' or 'binary'
                table.column("data_type", .text).notNull().defaults(to: "text")

                // Message content (text or base64-encoded binary)
                table.column("data", .blob)

                // Data size in bytes
                table.column("data_size", .integer).notNull().defaults(to: 0)

                // For SSE: lastEventId
                table.column("last_event_id", .text)

                // Timestamp when message was captured
                table.column("timestamp", .datetime).notNull()

                // Sequence number within connection
                table.column("sequence_num", .integer).notNull().defaults(to: 0)
        }

        try db.create(index: "idx_realtime_msg_conn", on: "realtime_messages", columns: ["connection_id"])
        try db.create(index: "idx_realtime_msg_session", on: "realtime_messages", columns: ["session_id"])
        try db.create(index: "idx_realtime_msg_timestamp", on: "realtime_messages", columns: ["timestamp"])
        try db.create(index: "idx_realtime_msg_direction", on: "realtime_messages", columns: ["direction"])
        try db.create(index: "idx_realtime_msg_event", on: "realtime_messages", columns: ["event_type"])
    }

    private static func createStreamChunksTable(_ db: Database) throws {
        try db.create(table: "stream_chunks") { table in
                // Primary key
                table.autoIncrementedPrimaryKey("id")

                // Reference to parent capture (the request that initiated the stream)
                table.column("capture_uuid", .text).notNull()

                // Session identifier
                table.column("session_id", .text)

                // Chunk index (order within the stream)
                table.column("chunk_index", .integer).notNull()

                // Chunk data
                table.column("data", .blob)

                // Chunk size in bytes
                table.column("chunk_size", .integer).notNull().defaults(to: 0)

                // Timestamp when chunk was received
                table.column("timestamp", .datetime).notNull()
        }

            // Create indexes for stream_chunks
        try db.create(index: "idx_stream_chunk_capture", on: "stream_chunks", columns: ["capture_uuid"])
        try db.create(index: "idx_stream_chunk_session", on: "stream_chunks", columns: ["session_id"])
        try db.create(
            index: "idx_stream_chunk_index",
            on: "stream_chunks",
            columns: ["capture_uuid", "chunk_index"]
        )
    }

    private static func addRealtimeColumnsToCaptures(_ db: Database) throws {
        try db.alter(table: "captures") { table in
            table.add(column: "traffic_type", .text).notNull().defaults(to: "http")
            table.add(column: "total_chunks", .integer)
            table.add(column: "total_bytes", .integer)
            table.add(column: "is_streaming", .boolean).notNull().defaults(to: false)
        }
        try db.create(index: "idx_captures_traffic_type", on: "captures", columns: ["traffic_type"])
    }

    /// v3: GraphQL operation metadata + multi-tab attribution; drops the vestigial filter columns.
    private static func registerV3Migration(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v3_graphql_tabs") { db in
            // Native ALTER ... DROP COLUMN (SQLite 3.35+); neither column is indexed, so the
            // other indexes survive untouched and existing row data is preserved in place.
            try db.alter(table: "captures") { table in
                table.add(column: "graphql_operation_name", .text)
                table.add(column: "graphql_operation_type", .text)
                table.add(column: "source_tab_id", .text)
                table.drop(column: "was_filtered")
                table.drop(column: "filter_reason")
            }
            try db.create(
                index: "idx_captures_graphql_op_type",
                on: "captures",
                columns: ["graphql_operation_type"]
            )
        }
    }
}

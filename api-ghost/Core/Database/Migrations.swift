import Foundation
import GRDB

struct Migrations {
    static func registerMigrations(_ migrator: inout DatabaseMigrator) {
        registerV1Migration(&migrator)
        registerV2Migration(&migrator)
        registerV3Migration(&migrator)
    }

    nonisolated private static func registerV1Migration(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v1_initial") { db in
            try db.create(table: "captures") { table in
                table.autoIncrementedPrimaryKey("id")

                table.column("uuid", .text).notNull().unique()

                table.column("timestamp", .datetime).notNull()

                table.column("session_id", .text)

                table.column("method", .text).notNull()
                table.column("scheme", .text).notNull()
                table.column("host", .text).notNull()
                table.column("port", .integer)
                table.column("path", .text).notNull()
                table.column("query", .text)
                table.column("request_headers", .text)
                table.column("request_body", .blob)
                table.column("request_body_size", .integer).notNull().defaults(to: 0)

                table.column("status_code", .integer)
                table.column("status_message", .text)
                table.column("response_headers", .text)
                table.column("response_body", .blob)
                table.column("response_body_size", .integer).notNull().defaults(to: 0)
                table.column("content_type", .text)

                table.column("duration_ms", .integer)

                table.column("was_filtered", .boolean).notNull().defaults(to: false)
                table.column("filter_reason", .text)
            }

            try db.create(index: "idx_captures_host", on: "captures", columns: ["host"])
            try db.create(index: "idx_captures_timestamp", on: "captures", columns: ["timestamp"])
            try db.create(index: "idx_captures_path", on: "captures", columns: ["path"])
            try db.create(index: "idx_captures_session_id", on: "captures", columns: ["session_id"])
            try db.create(index: "idx_captures_method", on: "captures", columns: ["method"])
            try db.create(index: "idx_captures_status_code", on: "captures", columns: ["status_code"])
        }
    }

    nonisolated private static func registerV2Migration(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v2_realtime_traffic") { db in
            try createRealtimeConnectionsTable(db)
            try createRealtimeMessagesTable(db)
            try createStreamChunksTable(db)
            try addRealtimeColumnsToCaptures(db)
        }
    }

    nonisolated private static func createRealtimeConnectionsTable(_ db: Database) throws {
        try db.create(table: "realtime_connections") { table in
                table.autoIncrementedPrimaryKey("id")

                table.column("connection_id", .text).notNull().unique()

                table.column("session_id", .text)

                table.column("connection_type", .text).notNull()

                table.column("url", .text).notNull()

                table.column("host", .text).notNull()

                table.column("path", .text).notNull()

                table.column("protocol", .text)
                table.column("extensions", .text)

                table.column("with_credentials", .boolean).notNull().defaults(to: false)

                table.column("opened_at", .datetime).notNull()
                table.column("closed_at", .datetime)

                table.column("duration_ms", .integer)

                table.column("status", .text).notNull().defaults(to: "connecting")

                table.column("close_code", .integer)
                table.column("close_reason", .text)
                table.column("was_clean", .boolean)

                table.column("messages_sent", .integer).notNull().defaults(to: 0)
                table.column("messages_received", .integer).notNull().defaults(to: 0)

                table.column("bytes_sent", .integer).notNull().defaults(to: 0)
                table.column("bytes_received", .integer).notNull().defaults(to: 0)
        }

        try db.create(index: "idx_realtime_conn_id", on: "realtime_connections", columns: ["connection_id"])
        try db.create(index: "idx_realtime_conn_type", on: "realtime_connections", columns: ["connection_type"])
        try db.create(index: "idx_realtime_conn_host", on: "realtime_connections", columns: ["host"])
        try db.create(index: "idx_realtime_conn_session", on: "realtime_connections", columns: ["session_id"])
        try db.create(index: "idx_realtime_conn_opened", on: "realtime_connections", columns: ["opened_at"])
    }

    nonisolated private static func createRealtimeMessagesTable(_ db: Database) throws {
        try db.create(table: "realtime_messages") { table in
                table.autoIncrementedPrimaryKey("id")

                table.column("connection_id", .text)
                    .notNull()
                    .references("realtime_connections", column: "connection_id", onDelete: .cascade)

                table.column("session_id", .text)

                table.column("direction", .text).notNull()

                table.column("event_type", .text).notNull()

                table.column("data_type", .text).notNull().defaults(to: "text")

                table.column("data", .blob)

                table.column("data_size", .integer).notNull().defaults(to: 0)

                table.column("last_event_id", .text)

                table.column("timestamp", .datetime).notNull()

                table.column("sequence_num", .integer).notNull().defaults(to: 0)
        }

        try db.create(index: "idx_realtime_msg_conn", on: "realtime_messages", columns: ["connection_id"])
        try db.create(index: "idx_realtime_msg_session", on: "realtime_messages", columns: ["session_id"])
        try db.create(index: "idx_realtime_msg_timestamp", on: "realtime_messages", columns: ["timestamp"])
        try db.create(index: "idx_realtime_msg_direction", on: "realtime_messages", columns: ["direction"])
        try db.create(index: "idx_realtime_msg_event", on: "realtime_messages", columns: ["event_type"])
    }

    nonisolated private static func createStreamChunksTable(_ db: Database) throws {
        try db.create(table: "stream_chunks") { table in
                table.autoIncrementedPrimaryKey("id")

                table.column("capture_uuid", .text).notNull()

                table.column("session_id", .text)

                table.column("chunk_index", .integer).notNull()

                table.column("data", .blob)

                table.column("chunk_size", .integer).notNull().defaults(to: 0)

                table.column("timestamp", .datetime).notNull()
        }

        try db.create(index: "idx_stream_chunk_capture", on: "stream_chunks", columns: ["capture_uuid"])
        try db.create(index: "idx_stream_chunk_session", on: "stream_chunks", columns: ["session_id"])
        try db.create(
            index: "idx_stream_chunk_index",
            on: "stream_chunks",
            columns: ["capture_uuid", "chunk_index"]
        )
    }

    nonisolated private static func addRealtimeColumnsToCaptures(_ db: Database) throws {
        try db.alter(table: "captures") { table in
            table.add(column: "traffic_type", .text).notNull().defaults(to: "http")
            table.add(column: "total_chunks", .integer)
            table.add(column: "total_bytes", .integer)
            table.add(column: "is_streaming", .boolean).notNull().defaults(to: false)
        }
        try db.create(index: "idx_captures_traffic_type", on: "captures", columns: ["traffic_type"])
    }

    nonisolated private static func registerV3Migration(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v3_graphql_tabs") { db in
            // Native ALTER ... DROP COLUMN needs SQLite 3.35+.
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

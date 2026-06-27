//
//  StreamChunk.swift
//  api-ghost
//
//  Created for APIGhost project
//  Represents a chunk of data from a streaming HTTP response.
//

import Foundation
import GRDB

/// Represents a single chunk from a streaming HTTP response.
/// Used to capture streaming responses like those from AI APIs.
struct StreamChunk: Codable, Sendable {
    // MARK: - Properties

    /// Auto-incremented database primary key
    var id: Int64?

    /// Reference to parent capture (the HTTP request that initiated the stream)
    let captureUUID: String

    /// Session identifier for quick filtering
    var sessionId: String?

    /// Chunk index (order within the stream, starting from 0)
    let chunkIndex: Int

    /// Chunk data
    var data: Data?

    /// Size of this chunk in bytes
    var chunkSize: Int

    /// Timestamp when chunk was received
    let timestamp: Date

    // MARK: - Initialization

    init(
        id: Int64? = nil,
        captureUUID: String,
        sessionId: String? = nil,
        chunkIndex: Int,
        data: Data? = nil,
        chunkSize: Int = 0,
        timestamp: Date = Date()
    ) {
        self.id = id
        self.captureUUID = captureUUID
        self.sessionId = sessionId
        self.chunkIndex = chunkIndex
        self.data = data
        self.chunkSize = chunkSize
        self.timestamp = timestamp
    }

    /// Creates a chunk from string data
    static func fromText(
        captureUUID: String,
        sessionId: String?,
        chunkIndex: Int,
        text: String
    ) -> StreamChunk {
        let data = text.data(using: .utf8)
        return StreamChunk(
            captureUUID: captureUUID,
            sessionId: sessionId,
            chunkIndex: chunkIndex,
            data: data,
            chunkSize: data?.count ?? 0
        )
    }
}

// MARK: - GRDB Protocols

extension StreamChunk: FetchableRecord, PersistableRecord {
    /// Database table name
    static let databaseTableName = "stream_chunks"

    /// Column to row key mapping
    enum Columns {
        static let id = Column(CodingKeys.id)
        static let captureUUID = Column(CodingKeys.captureUUID)
        static let sessionId = Column(CodingKeys.sessionId)
        static let chunkIndex = Column(CodingKeys.chunkIndex)
        static let data = Column(CodingKeys.data)
        static let chunkSize = Column(CodingKeys.chunkSize)
        static let timestamp = Column(CodingKeys.timestamp)
    }

    /// Custom column names to match database schema (snake_case)
    enum CodingKeys: String, CodingKey {
        case id
        case captureUUID = "capture_uuid"
        case sessionId = "session_id"
        case chunkIndex = "chunk_index"
        case data
        case chunkSize = "chunk_size"
        case timestamp
    }
}

// MARK: - Identifiable

extension StreamChunk: Identifiable {
    // id property is already defined
}

// MARK: - Computed Properties

extension StreamChunk {
    /// Returns the data as a string
    var dataString: String? {
        guard let data = data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Returns a truncated preview of the data
    var dataPreview: String {
        guard let str = dataString else {
            return "[No data]"
        }

        if str.count > 100 {
            return String(str.prefix(100)) + "..."
        }
        return str
    }
}

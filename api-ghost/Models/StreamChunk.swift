import Foundation
import GRDB

nonisolated struct StreamChunk: Codable, Sendable {
    // MARK: - Properties

    var id: Int64?

    let captureUUID: String

    var sessionId: String?

    let chunkIndex: Int

    var data: Data?

    var chunkSize: Int

    let timestamp: Date

    enum CodingKeys: String, CodingKey {
        case id
        case captureUUID = "capture_uuid"
        case sessionId = "session_id"
        case chunkIndex = "chunk_index"
        case data
        case chunkSize = "chunk_size"
        case timestamp
    }

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

extension StreamChunk: nonisolated FetchableRecord { }

extension StreamChunk: PersistableRecord {
    nonisolated static let databaseTableName = "stream_chunks"

    nonisolated enum Columns {
        static let id = Column(CodingKeys.id)
        static let captureUUID = Column(CodingKeys.captureUUID)
        static let sessionId = Column(CodingKeys.sessionId)
        static let chunkIndex = Column(CodingKeys.chunkIndex)
        static let data = Column(CodingKeys.data)
        static let chunkSize = Column(CodingKeys.chunkSize)
        static let timestamp = Column(CodingKeys.timestamp)
    }
}

// MARK: - Identifiable

extension StreamChunk: nonisolated Identifiable {
}

// MARK: - Computed Properties

extension StreamChunk {
    var dataString: String? {
        guard let data = data else { return nil }
        return String(data: data, encoding: .utf8)
    }

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

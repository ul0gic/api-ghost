import Foundation
import GRDB

final class CaptureStore: Sendable {
    // MARK: - Singleton

    static let shared = CaptureStore()

    // MARK: - Properties

    private let databaseManager: DatabaseManager

    private var database: DatabaseQueue? {
        databaseManager.database
    }

    // MARK: - Initialization

    init(databaseManager: DatabaseManager = .shared) {
        self.databaseManager = databaseManager
    }

    // MARK: - Create

    @discardableResult
    func save(_ capture: Capture) throws -> Capture {
        guard let db = database else {
            throw DatabaseError.notInitialized
        }
        return try db.write { db in
            try capture.inserted(db)
        }
    }

    @discardableResult
    func saveAll(_ captures: [Capture]) throws -> [Capture] {
        guard let db = database else {
            throw DatabaseError.notInitialized
        }
        return try db.write { db in
            try captures.map { try $0.inserted(db) }
        }
    }

    // MARK: - Read

    func fetchAll(limit: Int = 1000) throws -> [Capture] {
        guard let db = database else { return [] }
        return try db.read { db in
            try Capture
                .order(Column("timestamp").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    func fetch(byHost host: String) throws -> [Capture] {
        guard let db = database else { return [] }
        return try db.read { db in
            try Capture
                .filter(Column("host") == host)
                .order(Column("timestamp").desc)
                .fetchAll(db)
        }
    }

    func fetch(byUUID uuid: String) throws -> Capture? {
        guard let db = database else { return nil }
        return try db.read { db in
            try Capture
                .filter(Column("uuid") == uuid)
                .fetchOne(db)
        }
    }

    func fetch(bySessionId sessionId: String) throws -> [Capture] {
        guard let db = database else { return [] }
        return try db.read { db in
            try Capture
                .filter(Column("session_id") == sessionId)
                .order(Column("timestamp").desc)
                .fetchAll(db)
        }
    }

    func fetch(byMethod method: String) throws -> [Capture] {
        guard let db = database else { return [] }
        return try db.read { db in
            try Capture
                .filter(Column("method") == method)
                .order(Column("timestamp").desc)
                .fetchAll(db)
        }
    }

    func fetch(statusRange minStatus: Int, _ maxStatus: Int) throws -> [Capture] {
        guard let db = database else { return [] }
        return try db.read { db in
            try Capture
                .filter(Column("status_code") >= minStatus && Column("status_code") < maxStatus)
                .order(Column("timestamp").desc)
                .fetchAll(db)
        }
    }

    func fetchDomains() throws -> [(host: String, count: Int)] {
        guard let db = database else { return [] }
        return try db.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT host, COUNT(*) as count
                FROM captures
                GROUP BY host
                ORDER BY count DESC
            """)
            return rows.map { ($0["host"], $0["count"]) }
        }
    }

    func count() throws -> Int {
        guard let db = database else { return 0 }
        return try db.read { db in
            try Capture.fetchCount(db)
        }
    }

    func count(byHost host: String) throws -> Int {
        guard let db = database else { return 0 }
        return try db.read { db in
            try Capture
                .filter(Column("host") == host)
                .fetchCount(db)
        }
    }

    // MARK: - Update

    func update(_ capture: Capture) throws {
        guard let db = database else {
            throw DatabaseError.notInitialized
        }
        guard capture.id != nil else {
            throw CaptureStoreError.missingId
        }
        try db.write { db in
            try capture.update(db)
        }
    }

    // MARK: - Delete

    func deleteAll() throws {
        guard let db = database else {
            throw DatabaseError.notInitialized
        }
        try db.write { db in
            _ = try Capture.deleteAll(db)
        }
    }

    func delete(byUUID uuid: String) throws {
        guard let db = database else {
            throw DatabaseError.notInitialized
        }
        try db.write { db in
            _ = try Capture
                .filter(Column("uuid") == uuid)
                .deleteAll(db)
        }
    }

    @discardableResult
    func deleteOlderThan(_ date: Date) throws -> Int {
        guard let db = database else {
            throw DatabaseError.notInitialized
        }
        return try db.write { db in
            try Capture
                .filter(Column("timestamp") < date)
                .deleteAll(db)
        }
    }

    @discardableResult
    func delete(byHost host: String) throws -> Int {
        guard let db = database else {
            throw DatabaseError.notInitialized
        }
        return try db.write { db in
            try Capture
                .filter(Column("host") == host)
                .deleteAll(db)
        }
    }
}

// MARK: - Capture Store Errors

enum CaptureStoreError: Error, LocalizedError {
    case missingId
    case captureNotFound

    var errorDescription: String? {
        switch self {
        case .missingId:
            return "Capture must have an ID for update operations"
        case .captureNotFound:
            return "Capture not found in database"
        }
    }
}

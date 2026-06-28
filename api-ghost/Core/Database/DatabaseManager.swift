import Foundation
import GRDB
import os

nonisolated private let logger = Logger(subsystem: "corelift.api-ghost", category: "DatabaseManager")

nonisolated final class DatabaseManager: Sendable {
    enum StorageLocation: Sendable {
        case applicationSupport
        case file(path: String)
    }

    // MARK: - Singleton

    static let shared = DatabaseManager(location: .applicationSupport)

    // MARK: - Properties

    private let dbQueue: DatabaseQueue?
    private let databasePath: String?
    private let initializationError: Error?

    // MARK: - Initialization

    init(location: StorageLocation = .applicationSupport) {
        var tempQueue: DatabaseQueue?
        var tempPath: String?
        var tempError: Error?

        do {
            let (queue, path) = try DatabaseManager.createDatabase(at: location)
            tempQueue = queue
            tempPath = path

            var migrator = DatabaseMigrator()
            Migrations.registerMigrations(&migrator)
            try migrator.migrate(queue)

            logger.info("Database initialized at: \(path)")
        } catch {
            logger.error("Failed to initialize database: \(error)")
            tempError = error
        }

        self.dbQueue = tempQueue
        self.databasePath = tempPath
        self.initializationError = tempError
    }

    // MARK: - Public Interface

    var database: DatabaseQueue? {
        dbQueue
    }

    var path: String? {
        databasePath
    }

    func getDatabaseSize() -> String {
        guard let path = databasePath else { return "0 KB" }

        var totalSize: Int64 = 0
        let fileManager = FileManager.default

        if let attrs = try? fileManager.attributesOfItem(atPath: path),
           let size = attrs[.size] as? Int64 {
            totalSize += size
        }

        let walPath = path + "-wal"
        if let attrs = try? fileManager.attributesOfItem(atPath: walPath),
           let size = attrs[.size] as? Int64 {
            totalSize += size
        }

        let shmPath = path + "-shm"
        if let attrs = try? fileManager.attributesOfItem(atPath: shmPath),
           let size = attrs[.size] as? Int64 {
            totalSize += size
        }

        return ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }

    var isReady: Bool {
        dbQueue != nil
    }

    var error: Error? {
        initializationError
    }

    func getDatabaseSizeBytes() -> Int64 {
        guard let path = databasePath else { return 0 }

        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: path)
            if let size = attributes[.size] as? Int64 {
                return size
            }
        } catch {
            logger.error("Failed to get database size: \(error)")
        }

        return 0
    }

    func wipeAllData() throws {
        guard let db = dbQueue else {
            throw DatabaseError.notInitialized
        }

        try db.write { db in
            // Delete order matters due to foreign keys.
            try db.execute(sql: "DELETE FROM stream_chunks")
            try db.execute(sql: "DELETE FROM realtime_messages")
            try db.execute(sql: "DELETE FROM realtime_connections")
            try db.execute(sql: "DELETE FROM captures")
        }

        try vacuum()

        logger.info("All data wiped and database vacuumed")
    }

    func vacuum() throws {
        guard let db = dbQueue else {
            throw DatabaseError.notInitialized
        }

        // GRDB 7 writes are immediate transactions; a TRUNCATE checkpoint must run outside one.
        try db.writeWithoutTransaction { db in
            try db.execute(sql: "PRAGMA wal_checkpoint(TRUNCATE)")
        }

        try db.vacuum()
        logger.info("Database checkpointed and vacuumed")
    }

    // MARK: - Private Methods

    private static func createDatabase(at location: StorageLocation) throws -> (DatabaseQueue, String) {
        let dbPath = try resolveDatabasePath(for: location)

        var configuration = Configuration()
        configuration.prepareDatabase { db in
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }

        let queue = try DatabaseQueue(path: dbPath, configuration: configuration)

        return (queue, dbPath)
    }

    private static func resolveDatabasePath(for location: StorageLocation) throws -> String {
        switch location {
        case .applicationSupport:
            return try applicationSupportDatabasePath()
        case .file(let path):
            let directory = (path as NSString).deletingLastPathComponent
            if !directory.isEmpty {
                try FileManager.default.createDirectory(
                    atPath: directory,
                    withIntermediateDirectories: true
                )
            }
            return path
        }
    }

    private static func applicationSupportDatabasePath() throws -> String {
        let fileManager = FileManager.default

        let appSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        let dbDirectory = appSupport.appendingPathComponent("APIGhost", isDirectory: true)

        if !fileManager.fileExists(atPath: dbDirectory.path) {
            try fileManager.createDirectory(
                at: dbDirectory,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }

        return dbDirectory.appendingPathComponent("captures.db").path
    }
}

// MARK: - Database Errors

enum DatabaseError: Error, LocalizedError {
    case notInitialized
    case migrationFailed(String)

    var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "Database is not initialized"
        case .migrationFailed(let reason):
            return "Database migration failed: \(reason)"
        }
    }
}

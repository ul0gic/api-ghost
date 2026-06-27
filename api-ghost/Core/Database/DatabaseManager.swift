//
//  DatabaseManager.swift
//  api-ghost
//
//  Created for APIGhost project
//

import Foundation
import GRDB
import os

private let logger = Logger(subsystem: "corelift.api-ghost", category: "DatabaseManager")

/// Manages the SQLite database connection and lifecycle for APIGhost.
/// Thread-safe singleton providing database access throughout the application.
final class DatabaseManager: Sendable {
    // MARK: - Singleton

    static let shared = DatabaseManager()

    // MARK: - Properties

    private let dbQueue: DatabaseQueue?
    private let databasePath: String?
    private let initializationError: Error?

    // MARK: - Initialization

    private init() {
        var tempQueue: DatabaseQueue?
        var tempPath: String?
        var tempError: Error?

        do {
            let (queue, path) = try DatabaseManager.createDatabase()
            tempQueue = queue
            tempPath = path

            // Run migrations immediately after creating the database
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

    /// Returns the database queue for performing database operations.
    var database: DatabaseQueue? {
        dbQueue
    }

    /// Returns the path to the database file.
    var path: String? {
        databasePath
    }

    /// Returns a human-readable string representing the database file size.
    /// Includes main db file plus WAL and SHM files.
    func getDatabaseSize() -> String {
        guard let path = databasePath else { return "0 KB" }

        var totalSize: Int64 = 0
        let fileManager = FileManager.default

        // Main database file
        if let attrs = try? fileManager.attributesOfItem(atPath: path),
           let size = attrs[.size] as? Int64 {
            totalSize += size
        }

        // WAL file
        let walPath = path + "-wal"
        if let attrs = try? fileManager.attributesOfItem(atPath: walPath),
           let size = attrs[.size] as? Int64 {
            totalSize += size
        }

        // SHM file
        let shmPath = path + "-shm"
        if let attrs = try? fileManager.attributesOfItem(atPath: shmPath),
           let size = attrs[.size] as? Int64 {
            totalSize += size
        }

        return ByteCountFormatter.string(fromByteCount: totalSize, countStyle: .file)
    }

    /// Checks if the database is properly initialized and accessible.
    var isReady: Bool {
        dbQueue != nil
    }

    /// Returns the initialization error if database setup failed.
    var error: Error? {
        initializationError
    }

    /// Returns the database size in bytes.
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

    /// Wipes all data from the database.
    /// This deletes all captures, realtime data, and stream chunks, then vacuums.
    /// - Throws: DatabaseError if the wipe fails
    func wipeAllData() throws {
        guard let db = dbQueue else {
            throw DatabaseError.notInitialized
        }

        try db.write { db in
            // Delete from all tables (order matters due to foreign keys)
            try db.execute(sql: "DELETE FROM stream_chunks")
            try db.execute(sql: "DELETE FROM realtime_messages")
            try db.execute(sql: "DELETE FROM realtime_connections")
            try db.execute(sql: "DELETE FROM captures")
        }

        // Checkpoint WAL and vacuum to reclaim disk space
        try vacuum()

        logger.info("All data wiped and database vacuumed")
    }

    /// Vacuums the database to reclaim space after deletion.
    /// Checkpoints WAL first, then vacuums to fully reclaim space.
    /// - Throws: DatabaseError if vacuum fails
    func vacuum() throws {
        guard let db = dbQueue else {
            throw DatabaseError.notInitialized
        }

        // Checkpoint WAL to merge it into main database
        try db.write { db in
            try db.execute(sql: "PRAGMA wal_checkpoint(TRUNCATE)")
        }

        // Now vacuum to reclaim space
        try db.vacuum()
        logger.info("Database checkpointed and vacuumed")
    }

    // MARK: - Private Methods

    private static func createDatabase() throws -> (DatabaseQueue, String) {
        let fileManager = FileManager.default

        // Get Application Support directory
        let appSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )

        // Create APIGhost subdirectory
        let dbDirectory = appSupport.appendingPathComponent("APIGhost", isDirectory: true)

        if !fileManager.fileExists(atPath: dbDirectory.path) {
            try fileManager.createDirectory(
                at: dbDirectory,
                withIntermediateDirectories: true,
                attributes: nil
            )
        }

        // Database file path
        let dbPath = dbDirectory.appendingPathComponent("captures.db")

        // Configure database
        var configuration = Configuration()
        configuration.prepareDatabase { db in
            // Enable foreign keys
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }

        // Create database queue
        let queue = try DatabaseQueue(path: dbPath.path, configuration: configuration)

        return (queue, dbPath.path)
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

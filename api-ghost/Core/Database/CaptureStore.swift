//
//  CaptureStore.swift
//  api-ghost
//
//  Created for APIGhost project
//

import Foundation
import GRDB

/// Provides CRUD operations for Capture records in the database.
/// Thread-safe singleton for managing captured HTTP traffic data.
final class CaptureStore: Sendable {
    // MARK: - Singleton

    static let shared = CaptureStore()

    // MARK: - Properties

    private var database: DatabaseQueue? {
        DatabaseManager.shared.database
    }

    // MARK: - Initialization

    private init() {}

    // MARK: - Create

    /// Saves a capture to the database.
    /// - Parameter capture: The capture to save
    /// - Returns: The saved capture with its assigned database ID
    /// - Throws: Database errors if the save fails
    @discardableResult
    func save(_ capture: Capture) throws -> Capture {
        guard let db = database else {
            throw DatabaseError.notInitialized
        }
        return try db.write { db in
            // Use inserted() which returns the record with its new ID
            try capture.inserted(db)
        }
    }

    /// Saves multiple captures to the database in a single transaction.
    /// - Parameter captures: The captures to save
    /// - Returns: The saved captures with their assigned database IDs
    /// - Throws: Database errors if the save fails
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

    /// Fetches all captures, ordered by timestamp descending.
    /// - Parameter limit: Maximum number of captures to return (default 1000)
    /// - Returns: Array of captures
    /// - Throws: Database errors if the fetch fails
    func fetchAll(limit: Int = 1000) throws -> [Capture] {
        guard let db = database else { return [] }
        return try db.read { db in
            try Capture
                .order(Column("timestamp").desc)
                .limit(limit)
                .fetchAll(db)
        }
    }

    /// Fetches captures filtered by host.
    /// - Parameter host: The host to filter by
    /// - Returns: Array of captures matching the host
    /// - Throws: Database errors if the fetch fails
    func fetch(byHost host: String) throws -> [Capture] {
        guard let db = database else { return [] }
        return try db.read { db in
            try Capture
                .filter(Column("host") == host)
                .order(Column("timestamp").desc)
                .fetchAll(db)
        }
    }

    /// Fetches a single capture by its UUID.
    /// - Parameter uuid: The UUID to search for
    /// - Returns: The capture if found, nil otherwise
    /// - Throws: Database errors if the fetch fails
    func fetch(byUUID uuid: String) throws -> Capture? {
        guard let db = database else { return nil }
        return try db.read { db in
            try Capture
                .filter(Column("uuid") == uuid)
                .fetchOne(db)
        }
    }

    /// Fetches captures filtered by session ID.
    /// - Parameter sessionId: The session ID to filter by
    /// - Returns: Array of captures matching the session
    /// - Throws: Database errors if the fetch fails
    func fetch(bySessionId sessionId: String) throws -> [Capture] {
        guard let db = database else { return [] }
        return try db.read { db in
            try Capture
                .filter(Column("session_id") == sessionId)
                .order(Column("timestamp").desc)
                .fetchAll(db)
        }
    }

    /// Fetches captures filtered by HTTP method.
    /// - Parameter method: The HTTP method to filter by (GET, POST, etc.)
    /// - Returns: Array of captures matching the method
    /// - Throws: Database errors if the fetch fails
    func fetch(byMethod method: String) throws -> [Capture] {
        guard let db = database else { return [] }
        return try db.read { db in
            try Capture
                .filter(Column("method") == method)
                .order(Column("timestamp").desc)
                .fetchAll(db)
        }
    }

    /// Fetches captures filtered by status code range.
    /// - Parameters:
    ///   - minStatus: Minimum status code (inclusive)
    ///   - maxStatus: Maximum status code (exclusive)
    /// - Returns: Array of captures within the status range
    /// - Throws: Database errors if the fetch fails
    func fetch(statusRange minStatus: Int, _ maxStatus: Int) throws -> [Capture] {
        guard let db = database else { return [] }
        return try db.read { db in
            try Capture
                .filter(Column("status_code") >= minStatus && Column("status_code") < maxStatus)
                .order(Column("timestamp").desc)
                .fetchAll(db)
        }
    }

    /// Fetches a list of unique domains with their capture counts.
    /// - Returns: Array of tuples containing host and count
    /// - Throws: Database errors if the fetch fails
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

    /// Returns the total count of captures.
    /// - Returns: Total number of captures in the database
    /// - Throws: Database errors if the count fails
    func count() throws -> Int {
        guard let db = database else { return 0 }
        return try db.read { db in
            try Capture.fetchCount(db)
        }
    }

    /// Count of filtered captures persisted in the DB — always 0 since v3.
    func filteredCount() throws -> Int {
        // Filtered traffic is never persisted and the was_filtered column was removed in v3;
        // the live Filtered total is the in-memory session count (AppState.filteredRequestsCount).
        0
    }

    /// Returns the count of captures matching a specific host.
    /// - Parameter host: The host to count
    /// - Returns: Number of captures for the host
    /// - Throws: Database errors if the count fails
    func count(byHost host: String) throws -> Int {
        guard let db = database else { return 0 }
        return try db.read { db in
            try Capture
                .filter(Column("host") == host)
                .fetchCount(db)
        }
    }

    // MARK: - Update

    /// Updates an existing capture in the database.
    /// - Parameter capture: The capture to update (must have an ID)
    /// - Throws: Database errors if the update fails
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

    /// Deletes all captures from the database.
    /// - Throws: Database errors if the delete fails
    func deleteAll() throws {
        guard let db = database else {
            throw DatabaseError.notInitialized
        }
        try db.write { db in
            _ = try Capture.deleteAll(db)
        }
    }

    /// Deletes a capture by its UUID.
    /// - Parameter uuid: The UUID of the capture to delete
    /// - Throws: Database errors if the delete fails
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

    /// Deletes captures older than a specified date.
    /// - Parameter date: Delete captures older than this date
    /// - Returns: Number of deleted captures
    /// - Throws: Database errors if the delete fails
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

    /// Deletes all captures for a specific host.
    /// - Parameter host: The host whose captures should be deleted
    /// - Returns: Number of deleted captures
    /// - Throws: Database errors if the delete fails
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

// Endpoint aggregation, findings detection, and EndpointAggregation are in CaptureStore+Aggregation.swift

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

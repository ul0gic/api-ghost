import Foundation
import GRDB
import Testing

@testable import APIGhost

@Suite
struct MigrationRoundTripTests {
    private struct SeedRow {
        let uuid: String
        let method: String
        let host: String
        let path: String
        let statusCode: Int
        let wasFiltered: Bool
        let filterReason: String?
        let requestBody: Data?
    }

    private static let seedRows: [SeedRow] = [
        SeedRow(
            uuid: "RT-0001",
            method: "GET",
            host: "api.example.com",
            path: "/v1/users",
            statusCode: 200,
            wasFiltered: false,
            filterReason: nil,
            requestBody: nil
        ),
        SeedRow(
            uuid: "RT-0002",
            method: "POST",
            host: "api.example.com",
            path: "/v1/login",
            statusCode: 201,
            wasFiltered: false,
            filterReason: nil,
            requestBody: Data(#"{"user":"a"}"#.utf8)
        ),
        SeedRow(
            uuid: "RT-0003-legacy-filtered",
            method: "GET",
            host: "analytics.tracker.io",
            path: "/collect",
            statusCode: 200,
            wasFiltered: true,
            filterReason: "Analytics/Telemetry",
            requestBody: nil
        )
    ]

    private func makeMigrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()
        Migrations.registerMigrations(&migrator)
        return migrator
    }

    @Test
    func v3MigrationPreservesDataAndDropsFilterColumns() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).db")
        defer { try? FileManager.default.removeItem(at: url) }

        let queue = try DatabaseQueue(path: url.path)
        let migrator = makeMigrator()

        try migrator.migrate(queue, upTo: "v2_realtime_traffic")

        let preColumns = try queue.read { try $0.columns(in: "captures").map(\.name) }
        try #require(preColumns.contains("was_filtered"))
        try #require(preColumns.contains("filter_reason"))

        try queue.write { db in
            for row in Self.seedRows {
                try db.execute(
                    sql: """
                        INSERT INTO captures
                            (uuid, timestamp, method, scheme, host, path,
                             request_body, status_code, was_filtered, filter_reason)
                        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                        """,
                    arguments: [
                        row.uuid, Date(timeIntervalSince1970: 1_700_000_000), row.method, "https",
                        row.host, row.path, row.requestBody, row.statusCode,
                        row.wasFiltered, row.filterReason
                    ]
                )
            }
        }

        try migrator.migrate(queue)

        let postColumns = try queue.read { try $0.columns(in: "captures").map(\.name) }
        #expect(!postColumns.contains("was_filtered"))
        #expect(!postColumns.contains("filter_reason"))
        #expect(postColumns.contains("graphql_operation_name"))
        #expect(postColumns.contains("graphql_operation_type"))
        #expect(postColumns.contains("source_tab_id"))

        let captures = try queue.read { db in try Capture.order(Column("uuid")).fetchAll(db) }
        #expect(captures.count == Self.seedRows.count)

        let byUUID = Dictionary(uniqueKeysWithValues: captures.map { ($0.uuid, $0) })
        for seed in Self.seedRows {
            let capture = try #require(byUUID[seed.uuid], "row \(seed.uuid) must survive migration")
            #expect(capture.method == seed.method)
            #expect(capture.host == seed.host)
            #expect(capture.path == seed.path)
            #expect(capture.statusCode == seed.statusCode)
            #expect(capture.requestBody == seed.requestBody)
            #expect(capture.graphqlOperationName == nil)
            #expect(capture.sourceTabId == nil)
        }

        let legacy = try #require(byUUID["RT-0003-legacy-filtered"])
        #expect(legacy.host == "analytics.tracker.io")
    }
}

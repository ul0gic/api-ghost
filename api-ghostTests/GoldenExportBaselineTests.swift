//
//  GoldenExportBaselineTests.swift
//  api-ghostTests
//
//  Locks the export contract for SQLite, JSON, and HAR across the
//  includeHeaders/includeBodies paths (build-plan 1.1.2, regenerated for 1.2.4).
//
//  Post-v3 migration: was_filtered/filter_reason are gone and ExportManager's
//  `includeFiltered` flag is a no-op (fetchCaptures returns every stored row), so the
//  former filtered/unfiltered golden split collapsed into one golden per output shape.
//  The `includeFiltered` parameter is still exercised — via dedicated equivalence tests
//  proving true and false produce identical output.
//
//  Serialized: every test reseeds the single shared database, so they must not race.
//

import Foundation
import Testing

@testable import APIGhost

@MainActor
@Suite(.serialized)
struct GoldenExportBaselineTests {
    private func exportedURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    private func export(
        _ format: ExportFormat,
        includeHeaders: Bool,
        includeBodies: Bool,
        includeFiltered: Bool = false
    ) throws -> Data {
        try FixtureDatabase.reseed()
        let url = exportedURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try ExportManager.shared.export(
            to: url,
            format: format,
            includeHeaders: includeHeaders,
            includeBodies: includeBodies,
            includeFiltered: includeFiltered
        )
        return try Data(contentsOf: url)
    }

    // MARK: - JSON

    @Test func jsonHeadersBodies() throws {
        let data = try export(.json, includeHeaders: true, includeBodies: true)
        try Golden.verify(try OutputNormalizer.canonicalString(from: data), name: "json_headers_bodies.json")
    }

    @Test func jsonMinimal() throws {
        let data = try export(.json, includeHeaders: false, includeBodies: false)
        try Golden.verify(try OutputNormalizer.canonicalString(from: data), name: "json_minimal.json")
    }

    // MARK: - HAR

    @Test func harHeadersBodies() throws {
        let data = try export(.har, includeHeaders: true, includeBodies: true)
        try Golden.verify(try OutputNormalizer.canonicalString(from: data), name: "har_headers_bodies.json")
    }

    @Test func harMinimal() throws {
        let data = try export(.har, includeHeaders: false, includeBodies: false)
        try Golden.verify(try OutputNormalizer.canonicalString(from: data), name: "har_minimal.json")
    }

    // MARK: - SQLite

    @Test func sqliteContentPreserved() throws {
        try FixtureDatabase.reseed()
        let url = exportedURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try ExportManager.shared.export(to: url, format: .sqlite)
        try Golden.verify(try SQLiteContent.canonicalString(ofExportAt: url), name: "sqlite_content.json")
    }

    // MARK: - includeFiltered is now a no-op

    @Test func jsonIncludeFilteredIsNoOp() throws {
        let unfiltered = try export(.json, includeHeaders: true, includeBodies: true, includeFiltered: false)
        let filtered = try export(.json, includeHeaders: true, includeBodies: true, includeFiltered: true)
        #expect(try OutputNormalizer.canonicalString(from: unfiltered)
            == OutputNormalizer.canonicalString(from: filtered))
    }

    @Test func harIncludeFilteredIsNoOp() throws {
        let unfiltered = try export(.har, includeHeaders: true, includeBodies: true, includeFiltered: false)
        let filtered = try export(.har, includeHeaders: true, includeBodies: true, includeFiltered: true)
        #expect(try OutputNormalizer.canonicalString(from: unfiltered)
            == OutputNormalizer.canonicalString(from: filtered))
    }
}

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

    @Test
    func jsonHeadersBodies() throws {
        let data = try export(.json, includeHeaders: true, includeBodies: true)
        try Golden.verify(try OutputNormalizer.canonicalString(from: data), name: "json_headers_bodies.json")
    }

    @Test
    func jsonMinimal() throws {
        let data = try export(.json, includeHeaders: false, includeBodies: false)
        try Golden.verify(try OutputNormalizer.canonicalString(from: data), name: "json_minimal.json")
    }

    // MARK: - HAR

    @Test
    func harHeadersBodies() throws {
        let data = try export(.har, includeHeaders: true, includeBodies: true)
        try Golden.verify(try OutputNormalizer.canonicalString(from: data), name: "har_headers_bodies.json")
    }

    @Test
    func harMinimal() throws {
        let data = try export(.har, includeHeaders: false, includeBodies: false)
        try Golden.verify(try OutputNormalizer.canonicalString(from: data), name: "har_minimal.json")
    }

    // MARK: - SQLite

    @Test
    func sqliteContentPreserved() throws {
        try FixtureDatabase.reseed()
        let url = exportedURL()
        defer { try? FileManager.default.removeItem(at: url) }
        try ExportManager.shared.export(to: url, format: .sqlite)
        try Golden.verify(try SQLiteContent.canonicalString(ofExportAt: url), name: "sqlite_content.json")
    }

    // MARK: - includeFiltered is now a no-op

    @Test
    func jsonIncludeFilteredIsNoOp() throws {
        let unfiltered = try export(.json, includeHeaders: true, includeBodies: true, includeFiltered: false)
        let filtered = try export(.json, includeHeaders: true, includeBodies: true, includeFiltered: true)
        #expect(try OutputNormalizer.canonicalString(from: unfiltered)
            == OutputNormalizer.canonicalString(from: filtered))
    }

    @Test
    func harIncludeFilteredIsNoOp() throws {
        let unfiltered = try export(.har, includeHeaders: true, includeBodies: true, includeFiltered: false)
        let filtered = try export(.har, includeHeaders: true, includeBodies: true, includeFiltered: true)
        #expect(try OutputNormalizer.canonicalString(from: unfiltered)
            == OutputNormalizer.canonicalString(from: filtered))
    }
}

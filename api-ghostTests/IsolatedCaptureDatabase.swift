import Foundation

@testable import APIGhost

/// Per-test capture DB on its own temp file with dedicated store/exporter/map-builder, so parallel
/// suites never observe each other's writes (QA-006). Owns the temp directory for the test's lifetime.
final class IsolatedCaptureDatabase: Sendable {
    let manager: DatabaseManager
    let store: CaptureStore
    let exporter: ExportManager
    let mapBuilder: APIMapBuilder

    private let directory: URL

    init() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("apighost-tests-\(UUID().uuidString)", isDirectory: true)
        let manager = DatabaseManager(
            location: .file(path: directory.appendingPathComponent("captures.db").path)
        )
        if let error = manager.error { throw error }

        self.directory = directory
        self.manager = manager
        self.store = CaptureStore(databaseManager: manager)
        self.exporter = ExportManager(databaseManager: manager)
        self.mapBuilder = APIMapBuilder(databaseManager: manager)
    }

    @discardableResult
    func reseed(with captures: [Capture] = CaptureFixtures.all()) throws -> [Capture] {
        try manager.wipeAllData()
        return try store.saveAll(captures)
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }
}

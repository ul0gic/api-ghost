import Foundation
import Testing
import WebKit

@testable import APIGhost

// MARK: - Wipe vs. browsing-identity separation (3.3.3)

/// Wipe is SQLite-only; browsing identity lives in `WKWebsiteDataStore` and is preserved by construction.
/// Serialized + MainActor: mutates the shared DB and touches `@MainActor` WebKit types.
@MainActor
@Suite(.serialized)
struct WipeIdentitySeparationTests {
    // MARK: Wipe scope is exactly the DB

    @Test
    func wipeClearsCapturesButIsDatabaseOnly() async throws {
        try FixtureDatabase.assertIsolated()
        // Parallel suites reseed the shared DB, so prove the clear against a row no other writer touches.
        let host = "wipe-\(UUID().uuidString.prefix(8).lowercased()).qa.invalid"
        try CaptureStore.shared.save(Capture(method: "GET", scheme: "https", host: host, path: "/seed"))
        #expect(try CaptureStore.shared.count(byHost: host) == 1, "marker row seeded")

        try DatabaseManager.shared.wipeAllData()

        #expect(try CaptureStore.shared.count(byHost: host) == 0, "wipe clears the captures table")
    }

    // MARK: Identity store is persistent by construction

    @Test
    func browserTabUsesPersistentDataStore() {
        let manager = BrowserTabManager(dataStore: .default())
        defer { manager.activeTab.map { manager.closeTab($0.id) } }

        let store = try? #require(manager.activeTab).webView.configuration.websiteDataStore
        #expect(store?.isPersistent == true, "tabs browse on a persistent store, so login survives relaunch")
    }

    @Test
    func dataStorePersistenceContractHolds() {
        #expect(WKWebsiteDataStore.default().isPersistent == true)
        #expect(WKWebsiteDataStore.nonPersistent().isPersistent == false)
    }

    // MARK: Wipe does not reach into the browsing-identity store

    @Test
    func wipeDoesNotClearCookiesInTheDataStore() async throws {
        let identifier = UUID()
        let store = WKWebsiteDataStore(forIdentifier: identifier)
        defer { Task { try? await WKWebsiteDataStore.remove(forIdentifier: identifier) } }

        let cookie = try #require(HTTPCookie(properties: [
            .domain: "identity.test",
            .path: "/",
            .name: "session",
            .value: "preserved-\(identifier.uuidString)",
            .expires: Date().addingTimeInterval(3600)
        ]))
        await setCookie(cookie, in: store)

        try FixtureDatabase.reseed()
        try DatabaseManager.shared.wipeAllData()

        let names = await allCookies(in: store).map(\.name)
        #expect(names.contains("session"), "a DB wipe leaves the WKWebsiteDataStore cookies untouched")
    }

    // MARK: WebKit cookie-store bridges

    private func setCookie(_ cookie: HTTPCookie, in store: WKWebsiteDataStore) async {
        await withCheckedContinuation { continuation in
            store.httpCookieStore.setCookie(cookie) { continuation.resume() }
        }
    }

    private func allCookies(in store: WKWebsiteDataStore) async -> [HTTPCookie] {
        await withCheckedContinuation { continuation in
            store.httpCookieStore.getAllCookies { continuation.resume(returning: $0) }
        }
    }
}

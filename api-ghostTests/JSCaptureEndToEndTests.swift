import Foundation
import Testing

@testable import APIGhost

// MARK: - JS-mode end-to-end capture (3.5.1)

/// Drives the real bridge entry point (`JSMessageHandler.userContentController`) the way the JS bridge does.
/// Suites run in parallel over shared singletons, so every assertion is scoped to a host no other writer uses.
@MainActor
@Suite(.serialized)
struct JSCaptureEndToEndTests {
    private func makeHandler(sourceTabId: String? = nil) -> JSMessageHandler {
        let handler = JSMessageHandler()
        handler.sourceTabId = sourceTabId
        return handler
    }

    private func prepare(capturing: Bool = true) {
        TrafficCapture.shared.isCapturing = capturing
        NoiseFilter.shared.isEnabled = true
        TrafficCapture.shared.clearRecentCaptures()
    }

    /// `store()` appends to `recentCaptures` and persists to the captures table in one unbranched path, so the
    /// in-memory mirror is the deterministic signal; the SQLite write itself is owned by the DB-seeded suites.
    /// A positive shared-DB-row assertion can't be deterministic here — parallel DB suites wipe the table mid-read.
    @Test
    func normalRequestIsCaptured() async throws {
        prepare()
        defer { TrafficCapture.shared.isCapturing = false }
        let host = CaptureBridge.uniqueHost("normal")

        CaptureBridge.capture(
            through: makeHandler(),
            url: "https://\(host)/v1/users",
            method: "GET"
        )

        let captured = try #require(await CaptureBridge.waitForRecent(host: host))
        #expect(captured.method == "GET")
        #expect(captured.path == "/v1/users")
        #expect(captured.statusCode == 200)
    }

    @Test
    func filteredRequestIsDroppedWhileSiblingIsCaptured() async throws {
        prepare()
        defer { TrafficCapture.shared.isCapturing = false }
        let handler = makeHandler()
        let allowedHost = CaptureBridge.uniqueHost("allowed")
        let filteredHost = CaptureBridge.uniqueHost("filtered")

        // `/collect` matches the analytics category (enabled by default in DefaultBlocklist.json) → dropped.
        CaptureBridge.capture(through: handler, url: "https://\(filteredHost)/collect", method: "GET")
        // Control on the same handler proves the pipeline ran and the drop was selective.
        CaptureBridge.capture(through: handler, url: "https://\(allowedHost)/v1/users", method: "GET")

        _ = try #require(await CaptureBridge.waitForRecent(host: allowedHost), "the sibling request is captured")
        #expect(await CaptureBridge.confirmNeverCaptured(host: filteredHost),
                "a request matching an enabled filter category is dropped, never stored")
        #expect(try await CaptureBridge.waitForDBRow(host: filteredHost, timeout: 0.3) == nil,
                "no captures row exists for the dropped request")
    }

    @Test
    func graphQLPostPopulatesOperationColumns() async throws {
        prepare()
        defer { TrafficCapture.shared.isCapturing = false }
        let host = CaptureBridge.uniqueHost("gql")

        let body = #"{"operationName":"GetUser","query":"query GetUser { user { id } }"}"#
        CaptureBridge.capture(
            through: makeHandler(),
            url: "https://\(host)/graphql",
            method: "POST",
            requestHeaders: ["Content-Type": "application/json"],
            requestBody: body
        )

        let captured = try #require(await CaptureBridge.waitForRecent(host: host))
        #expect(captured.graphqlOperationName == "GetUser")
        #expect(captured.graphqlOperationType == "query")
    }

    @Test
    func captureIsStampedWithSourceTabId() async throws {
        prepare()
        defer { TrafficCapture.shared.isCapturing = false }
        let host = CaptureBridge.uniqueHost("tab")
        let tabId = "tab-7F3A9C21"

        CaptureBridge.capture(
            through: makeHandler(sourceTabId: tabId),
            url: "https://\(host)/v1/orders",
            method: "GET"
        )

        let captured = try #require(await CaptureBridge.waitForRecent(host: host))
        #expect(captured.sourceTabId == tabId, "the row carries the tab id the handler was configured with")
    }

    @Test
    func nothingIsCapturedWhileSessionIsPaused() async throws {
        prepare(capturing: false)
        let host = CaptureBridge.uniqueHost("paused")

        CaptureBridge.capture(through: makeHandler(), url: "https://\(host)/v1/users")

        #expect(await CaptureBridge.confirmNeverCaptured(host: host), "a paused session ingests nothing")
    }
}

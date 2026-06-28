import Foundation
import WebKit

@testable import APIGhost

/// Overrides only `body`/`name` so we can drive `JSMessageHandler.userContentController` exactly as the JS bridge does.
final class FakeScriptMessage: WKScriptMessage {
    private let payload: Any

    init(payload: Any) {
        self.payload = payload
        super.init()
    }

    override var body: Any { payload }
    override var name: String { JSMessageHandler.handlerName }
}

/// Process-wide async mutex. The capture-pipeline suites share `TrafficCapture.shared` global state
/// (`isCapturing`, `recentCaptures`), so each test holds this across its whole body — `.serialized` only
/// orders tests within one suite, not the parallel suites that would otherwise stomp the singleton (QA-006).
actor CaptureStateGate {
    static let shared = CaptureStateGate()
    private var locked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func acquire() async {
        guard locked else { locked = true; return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func release() {
        if waiters.isEmpty { locked = false } else { waiters.removeFirst().resume() }
    }
}

@MainActor
enum CaptureBridge {
    static let dummyController = WKUserContentController()

    /// Runs `body` with exclusive ownership of the shared capture state, releasing on success and on throw.
    static func withExclusiveCaptureState<T>(_ body: @MainActor () async throws -> T) async rethrows -> T {
        await CaptureStateGate.shared.acquire()
        do {
            let result = try await body()
            await CaptureStateGate.shared.release()
            return result
        } catch {
            await CaptureStateGate.shared.release()
            throw error
        }
    }

    static func deliver(_ payload: [String: Any], to handler: JSMessageHandler) {
        handler.userContentController(dummyController, didReceive: FakeScriptMessage(payload: payload))
    }

    static func requestPayload(
        id: String,
        url: String,
        method: String = "GET",
        headers: [String: String] = ["Accept": "application/json"],
        body: String? = nil,
        isBeacon: Bool = false
    ) -> [String: Any] {
        var dict: [String: Any] = [
            "type": "request",
            "id": id,
            "url": url,
            "method": method,
            "headers": headers,
            "timestamp": Date().timeIntervalSince1970 * 1000,
            "isBeacon": isBeacon
        ]
        if let body { dict["body"] = body }
        return dict
    }

    static func responsePayload(
        id: String,
        status: Int = 200,
        statusText: String = "OK",
        headers: [String: String] = ["Content-Type": "application/json"],
        body: String? = #"{"ok":true}"#,
        duration: Int = 10
    ) -> [String: Any] {
        var dict: [String: Any] = [
            "type": "response",
            "id": id,
            "status": status,
            "statusText": statusText,
            "headers": headers,
            "duration": duration
        ]
        if let body { dict["body"] = body }
        return dict
    }

    /// Drives one request+response pair through the handler the way the bridge does.
    static func capture(
        through handler: JSMessageHandler,
        id: String = UUID().uuidString,
        url: String,
        method: String = "GET",
        requestHeaders: [String: String] = ["Accept": "application/json"],
        requestBody: String? = nil,
        responseContentType: String = "application/json"
    ) {
        deliver(
            requestPayload(id: id, url: url, method: method, headers: requestHeaders, body: requestBody),
            to: handler
        )
        deliver(
            responsePayload(id: id, headers: ["Content-Type": responseContentType]),
            to: handler
        )
    }

    /// Suites run in parallel and share global singletons, so isolate every assertion to a host no other writer uses.
    static func uniqueHost(_ tag: String) -> String {
        "\(tag)-\(UUID().uuidString.prefix(8).lowercased()).qa.invalid"
    }

    /// `recentCaptures` is the in-memory mirror of the same `store()` call — immune to other suites' DB reseeds/wipes.
    static func waitForRecent(host: String, timeout: TimeInterval = 3) async -> Capture? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let match = TrafficCapture.shared.recentCaptures.first(where: { $0.host == host }) {
                return match
            }
            try? await Task.sleep(nanoseconds: 15_000_000)
        }
        return TrafficCapture.shared.recentCaptures.first { $0.host == host }
    }

    /// The async store path also persists to SQLite; poll the isolated DB for the row by its unique host.
    static func waitForDBRow(host: String, timeout: TimeInterval = 3) async throws -> Capture? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let row = try CaptureStore.shared.fetch(byHost: host).first { return row }
            try await Task.sleep(nanoseconds: 15_000_000)
        }
        return try CaptureStore.shared.fetch(byHost: host).first
    }

    /// Proves a drop by confirming the unique host never appears in `recentCaptures` across a settle window.
    static func confirmNeverCaptured(host: String, window: TimeInterval = 0.4) async -> Bool {
        let deadline = Date().addingTimeInterval(window)
        while Date() < deadline {
            if TrafficCapture.shared.recentCaptures.contains(where: { $0.host == host }) { return false }
            try? await Task.sleep(nanoseconds: 15_000_000)
        }
        return !TrafficCapture.shared.recentCaptures.contains { $0.host == host }
    }
}

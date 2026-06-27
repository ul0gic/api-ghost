import Foundation
import GRDB
import Testing

@testable import APIGhost

// MARK: - Deterministic capture fixtures

enum CaptureFixtures {
    static let baseEpoch: TimeInterval = 1_700_000_000

    static func all() -> [Capture] {
        [
            getWithQuery(),
            postWithBody(),
            sparseGet404(),
            analyticsBeacon(),
            postOnPort500(),
            requestWithoutResponse()
        ]
    }

    private static func at(_ offset: TimeInterval) -> Date {
        Date(timeIntervalSince1970: baseEpoch + offset)
    }

    private static func body(_ string: String) -> Data { Data(string.utf8) }

    static func getWithQuery() -> Capture {
        let response = body(#"{"ok":true}"#)
        return Capture(
            uuid: "00000000-0000-0000-0000-0000000000A1",
            timestamp: at(5),
            sessionId: "session-fixed",
            method: "GET",
            scheme: "https",
            host: "api.example.com",
            path: "/v1/users",
            query: "page=2&limit=10",
            requestHeaders: #"{"Accept":"application/json","X-Trace-Id":"abc"}"#,
            requestBodySize: 0,
            statusCode: 200,
            statusMessage: "OK",
            responseHeaders: #"{"Content-Type":"application/json","X-RateLimit":"99"}"#,
            responseBody: response,
            responseBodySize: response.count,
            contentType: "application/json",
            durationMs: 42
        )
    }

    static func postWithBody() -> Capture {
        let request = body(#"{"user":"a","pass":"b"}"#)
        let response = body(#"{"token":"xyz"}"#)
        return Capture(
            uuid: "00000000-0000-0000-0000-0000000000A2",
            timestamp: at(4),
            sessionId: "session-fixed",
            method: "POST",
            scheme: "https",
            host: "api.example.com",
            path: "/v1/login",
            requestHeaders: #"{"Content-Type":"application/json"}"#,
            requestBody: request,
            requestBodySize: request.count,
            statusCode: 201,
            statusMessage: "Created",
            responseHeaders: #"{"Content-Type":"application/json"}"#,
            responseBody: response,
            responseBodySize: response.count,
            contentType: "application/json",
            durationMs: 88
        )
    }

    static func sparseGet404() -> Capture {
        Capture(
            uuid: "00000000-0000-0000-0000-0000000000A3",
            timestamp: at(3),
            method: "GET",
            scheme: "http",
            host: "cdn.example.org",
            path: "/missing.png"
        )
    }

    static func analyticsBeacon() -> Capture {
        Capture(
            uuid: "00000000-0000-0000-0000-0000000000A4",
            timestamp: at(2),
            method: "GET",
            scheme: "https",
            host: "analytics.tracker.io",
            path: "/collect",
            query: "v=1&t=pageview",
            requestHeaders: #"{"Accept":"*/*"}"#,
            statusCode: 200,
            statusMessage: "OK",
            durationMs: 7
        )
    }

    static func postOnPort500() -> Capture {
        let request = body(#"{"item":42}"#)
        let response = body("boom")
        return Capture(
            uuid: "00000000-0000-0000-0000-0000000000A5",
            timestamp: at(1),
            method: "POST",
            scheme: "https",
            host: "api.example.com",
            port: 8443,
            path: "/v1/orders",
            query: "",
            requestHeaders: #"{"Content-Type":"application/json"}"#,
            requestBody: request,
            requestBodySize: request.count,
            statusCode: 500,
            statusMessage: "Internal Server Error",
            responseHeaders: #"{"Content-Type":"text/plain"}"#,
            responseBody: response,
            responseBodySize: response.count,
            contentType: "text/plain",
            durationMs: 1200
        )
    }

    static func requestWithoutResponse() -> Capture {
        Capture(
            uuid: "00000000-0000-0000-0000-0000000000A6",
            timestamp: at(0),
            method: "GET",
            scheme: "https",
            host: "api.example.com",
            path: "/v1/ping",
            requestHeaders: #"{"Accept":"application/json"}"#
        )
    }
}

// MARK: - Isolated database seeding

enum FixtureDatabase {
    enum FixtureError: Error, CustomStringConvertible {
        case unsafeDatabasePath(String)

        var description: String {
            switch self {
            case .unsafeDatabasePath(let path):
                return """
                Refusing to seed: database is not isolated (path: \(path)). \
                Run via the shared 'api-ghost' scheme so CFFIXED_USER_HOME redirects \
                the DB into an isolated test home.
                """
            }
        }
    }

    static let isolationSentinel = "TestHome"

    static func assertIsolated() throws {
        let path = DatabaseManager.shared.path ?? ""
        guard path.contains(isolationSentinel) else {
            throw FixtureError.unsafeDatabasePath(path)
        }
    }

    static func reseed(with captures: [Capture] = CaptureFixtures.all()) throws {
        try assertIsolated()
        try DatabaseManager.shared.wipeAllData()
        try CaptureStore.shared.saveAll(captures)
    }
}

// MARK: - Output normalization

enum OutputNormalizer {
    static func canonicalString(from data: Data) throws -> String {
        let object = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        let normalized = normalize(object)
        let canonical = try JSONSerialization.data(
            withJSONObject: normalized,
            options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed]
        )
        return String(decoding: canonical, as: UTF8.self)
    }

    static func canonicalString(from object: Any) throws -> String {
        let canonical = try JSONSerialization.data(
            withJSONObject: normalize(object),
            options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed]
        )
        return String(decoding: canonical, as: UTF8.self)
    }

    private static func normalize(_ value: Any) -> Any {
        if let dict = value as? [String: Any] {
            return dict.mapValues { normalize($0) }
        }
        if let array = value as? [Any] {
            let mapped = array.map { normalize($0) }
            if isNameValueArray(mapped) {
                return mapped.sorted { lhs, rhs in compareNameValue(lhs, rhs) }
            }
            return mapped
        }
        return value
    }

    private static func isNameValueArray(_ array: [Any]) -> Bool {
        guard !array.isEmpty else { return false }
        return array.allSatisfy { ($0 as? [String: Any])?["name"] is String }
    }

    private static func compareNameValue(_ lhs: Any, _ rhs: Any) -> Bool {
        let left = lhs as? [String: Any]
        let right = rhs as? [String: Any]
        let leftName = left?["name"] as? String ?? ""
        let rightName = right?["name"] as? String ?? ""
        if leftName != rightName { return leftName < rightName }
        let leftValue = left?["value"] as? String ?? ""
        let rightValue = right?["value"] as? String ?? ""
        return leftValue < rightValue
    }
}

// MARK: - SQLite content extraction

enum SQLiteContent {
    static func canonicalString(ofExportAt url: URL) throws -> String {
        let queue = try DatabaseQueue(path: url.path)
        let captures = try queue.read { db in
            try Capture.order(Column("uuid")).fetchAll(db)
        }
        let rows = captures.map { dictionary(for: $0) }
        return try OutputNormalizer.canonicalString(from: rows)
    }

    private static func dictionary(for capture: Capture) -> [String: Any] {
        var dict: [String: Any] = [
            "uuid": capture.uuid,
            "timestamp": ISO8601DateFormatter().string(from: capture.timestamp),
            "method": capture.method,
            "scheme": capture.scheme,
            "host": capture.host,
            "path": capture.path,
            "requestBodySize": capture.requestBodySize,
            "responseBodySize": capture.responseBodySize,
            "trafficType": capture.trafficType.rawValue,
            "isStreaming": capture.isStreaming
        ]
        dict["port"] = capture.port
        dict["query"] = capture.query
        dict["sessionId"] = capture.sessionId
        dict["requestHeaders"] = capture.requestHeaders
        dict["responseHeaders"] = capture.responseHeaders
        dict["requestBody"] = capture.requestBody.flatMap { String(data: $0, encoding: .utf8) }
        dict["responseBody"] = capture.responseBody.flatMap { String(data: $0, encoding: .utf8) }
        dict["statusCode"] = capture.statusCode
        dict["statusMessage"] = capture.statusMessage
        dict["contentType"] = capture.contentType
        dict["durationMs"] = capture.durationMs
        dict["graphqlOperationName"] = capture.graphqlOperationName
        dict["graphqlOperationType"] = capture.graphqlOperationType
        dict["sourceTabId"] = capture.sourceTabId
        return dict.compactMapValues { $0 }
    }
}

// MARK: - Golden file IO

enum Golden {
    static func goldenDirectory(file: StaticString = #filePath) -> URL {
        URL(fileURLWithPath: "\(file)")
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/golden", isDirectory: true)
    }

    static func verify(_ actual: String, name: String) throws {
        let directory = goldenDirectory()
        let url = directory.appendingPathComponent(name)
        let recording = ProcessInfo.processInfo.environment["RECORD_GOLDEN"] != nil
        let exists = FileManager.default.fileExists(atPath: url.path)

        if recording || !exists {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try actual.write(to: url, atomically: true, encoding: .utf8)
            if !recording {
                Issue.record("Golden '\(name)' was missing and has been generated; re-run to verify.")
            }
            return
        }

        let expected = try String(contentsOf: url, encoding: .utf8)
        if actual != expected {
            let actualURL = directory.appendingPathComponent(name + ".actual")
            try? actual.write(to: actualURL, atomically: true, encoding: .utf8)
        }
        #expect(actual == expected, "Export output diverged from golden '\(name)'")
    }
}

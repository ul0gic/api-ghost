import Foundation
import SwiftMITM
import os

nonisolated private let logger = Logger(subsystem: "corelift.api-ghost", category: "ProxyCaptureSink")

/// Bridges engine `CaptureEvent`s into the JS-mode pipeline (NoiseFilter → GraphQLParser → CaptureStore).
/// Bodies arrive bounded by `captureBodyLimit`; the sink concatenates, decodes Content-Encoding, and stores them to match JS-mode.
final class ProxyCaptureSink: CaptureEventSink, @unchecked Sendable {
    fileprivate struct Pending: Sendable {
        let request: CapturedRequestHead
        var requestBody: Data
        var requestBodyBytes: Int
        var requestTruncated: Bool
        var response: CapturedResponseHead?
        var responseBody: Data
        var responseBodyBytes: Int
        var responseTruncated: Bool

        init(request: CapturedRequestHead) {
            self.request = request
            requestBody = Data()
            requestBodyBytes = 0
            requestTruncated = false
            response = nil
            responseBody = Data()
            responseBodyBytes = 0
            responseTruncated = false
        }
    }

    /// Bounds in-flight tracking so abandoned streams (no responseEnd) can't grow `pending` without limit (BUG-004).
    private static let maxPendingEntries = 1024

    private let lock = NSLock()
    private var pending: [UUID: Pending] = [:]

    func receive(_ event: CaptureEvent) {
        switch event {
        case .requestHead(let head):
            withLock {
                pending[head.id] = Pending(request: head)
                evictOldestIfNeeded()
            }
        case let .requestBodyChunk(requestID, bytes, byteCount):
            withLock {
                pending[requestID]?.requestBody.append(contentsOf: bytes)
                pending[requestID]?.requestBodyBytes += byteCount
            }
        case let .requestEnd(requestID, truncated):
            withLock { pending[requestID]?.requestTruncated = truncated }
        case .responseHead(let head):
            withLock { pending[head.requestID]?.response = head }
        case let .responseBodyChunk(requestID, bytes, byteCount):
            withLock {
                pending[requestID]?.responseBody.append(contentsOf: bytes)
                pending[requestID]?.responseBodyBytes += byteCount
            }
        case let .responseEnd(requestID, truncated):
            let record = withLock { () -> Pending? in
                pending[requestID]?.responseTruncated = truncated
                return pending.removeValue(forKey: requestID)
            }
            guard let record else { return }
            Task { await Self.finalize(record) }
        case let .streamError(requestID, message):
            withLock { _ = pending.removeValue(forKey: requestID) }
            logger.debug("Proxy stream error \(requestID): \(message)")
        }
    }

    /// Drops all in-flight tracking; call when the proxy stops so buffered bodies of abandoned streams are released (BUG-004).
    func reset() {
        withLock { pending.removeAll() }
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    /// Caller must hold `lock`. Evicts the oldest in-flight entry by request timestamp when over the cap.
    private func evictOldestIfNeeded() {
        guard pending.count > Self.maxPendingEntries else { return }
        if let oldest = pending.min(by: { $0.value.request.timestamp < $1.value.request.timestamp })?.key {
            pending.removeValue(forKey: oldest)
        }
    }
}

// MARK: - Finalization (JS-mode parity)

private extension ProxyCaptureSink {
    /// Heavy finalization (decode, GraphQL parse, header encode) runs off the main actor; only the capture-gate and
    /// store hop to the main actor where `TrafficCapture`/`Preferences` live (SEC-006, PRF-001).
    nonisolated static func finalize(_ record: Pending) async {
        let resolved = Resolved(record)
        let gate = await MainActor.run { () -> (sessionId: String, maxDecoded: Int)? in
            guard TrafficCapture.shared.isCapturing else { return nil }
            let decision = NoiseFilter.shared.shouldCapture(
                host: resolved.host,
                path: resolved.path,
                contentType: resolved.contentType,
                responseSize: record.responseBodyBytes
            )
            guard decision.shouldCapture else {
                TrafficCapture.shared.recordFiltered()
                return nil
            }
            return (TrafficCapture.shared.sessionId, Preferences.shared.maxResponseSize)
        }
        guard let gate else { return }

        let capture = buildCapture(
            record: record,
            resolved: resolved,
            sessionId: gate.sessionId,
            maxDecodedSize: gate.maxDecoded
        )
        await MainActor.run {
            guard TrafficCapture.shared.isCapturing else { return }
            TrafficCapture.shared.store(capture)
        }
    }

    /// Fields derived once from the engine heads — the bridge from `CaptureEvent` semantics to the `Capture` row.
    nonisolated struct Resolved: Sendable {
        let host: String
        let port: Int?
        let path: String
        let query: String?
        let requestHeaders: [String: String]
        let responseHeaders: [String: String]?
        let contentType: String?

        init(_ record: Pending) {
            let head = record.request
            (host, port) = splitAuthority(head.authority, scheme: head.scheme)
            (path, query) = splitPathQuery(head.path)
            requestHeaders = dictionary(head.headers)
            responseHeaders = record.response.map { dictionary($0.headers) }
            contentType = responseHeaders.flatMap { headerValue($0, "content-type")?.beforeSemicolon }
        }
    }

    nonisolated static func buildCapture(
        record: Pending,
        resolved: Resolved,
        sessionId: String,
        maxDecodedSize: Int
    ) -> Capture {
        let head = record.request
        let isWebSocket = isWebSocket(requestHeaders: resolved.requestHeaders, status: record.response?.status)
        let requestBody = decodedBody(
            record.requestBody,
            headers: resolved.requestHeaders,
            truncated: record.requestTruncated,
            maxDecodedSize: maxDecodedSize
        )
        let responseBody = decodedBody(
            record.responseBody,
            headers: resolved.responseHeaders ?? [:],
            truncated: record.responseTruncated,
            maxDecodedSize: maxDecodedSize
        )
        let url = buildURL(scheme: head.scheme, resolved: resolved)
        let requestContentType = headerValue(resolved.requestHeaders, "content-type")
        let graphql = url.flatMap {
            GraphQLParser.parse(method: head.method, url: $0, contentType: requestContentType, body: requestBody)
        }

        return Capture(
            sessionId: sessionId,
            method: head.method,
            scheme: head.scheme,
            host: resolved.host,
            port: resolved.port,
            path: resolved.path,
            query: resolved.query,
            requestHeaders: encodeHeaders(resolved.requestHeaders),
            requestBody: requestBody,
            requestBodySize: record.requestBodyBytes,
            statusCode: record.response?.status,
            statusMessage: nil,
            responseHeaders: resolved.responseHeaders.flatMap { encodeHeaders($0) },
            responseBody: responseBody,
            responseBodySize: record.responseBodyBytes,
            contentType: resolved.contentType,
            durationMs: Int(Date().timeIntervalSince(head.timestamp) * 1000),
            graphqlOperationName: graphql?.operationName,
            graphqlOperationType: graphql?.storedOperationType,
            sourceTabId: nil,
            trafficType: isWebSocket ? .streaming : .http,
            isStreaming: isWebSocket,
            totalBytes: isWebSocket ? record.responseBodyBytes : nil
        )
    }

    /// Decodes Content-Encoding to match JS-mode body output; empty/absent bodies map to nil.
    nonisolated static func decodedBody(
        _ body: Data,
        headers: [String: String],
        truncated: Bool,
        maxDecodedSize: Int
    ) -> Data? {
        guard !body.isEmpty else { return nil }
        let encoding = headerValue(headers, "content-encoding")
        let decoded = HTTPBodyDecoder.decode(
            body,
            contentEncoding: encoding,
            truncated: truncated,
            maxDecodedSize: maxDecodedSize
        )
        return decoded.isEmpty ? nil : decoded
    }

    nonisolated static func encodeHeaders(_ headers: [String: String]) -> String? {
        guard let data = try? JSONEncoder().encode(headers) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    nonisolated static func buildURL(scheme: String, resolved: Resolved) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = resolved.host
        components.port = resolved.port
        components.path = resolved.path
        components.percentEncodedQuery = resolved.query
        return components.url
    }

    /// Covers WS-over-HTTP/1.1 (Upgrade handshake / 101). WS-over-h2 (RFC 8441) is not proxied — capture it in JS-injection mode.
    nonisolated static func isWebSocket(requestHeaders: [String: String], status: Int?) -> Bool {
        if status == 101 { return true }
        return headerValue(requestHeaders, "upgrade")?.lowercased().contains("websocket") ?? false
    }

    nonisolated static func dictionary(_ fields: [HTTPHeaderField]) -> [String: String] {
        var dict: [String: String] = [:]
        for field in fields { dict[field.name] = field.value }
        return dict
    }

    nonisolated static func headerValue(_ headers: [String: String], _ name: String) -> String? {
        let target = name.lowercased()
        for (key, value) in headers where key.lowercased() == target { return value }
        return nil
    }

    nonisolated static func splitAuthority(_ authority: String, scheme: String) -> (host: String, port: Int?) {
        var host = authority
        var port: Int? = scheme == "http" ? 80 : 443
        if authority.hasPrefix("["), let close = authority.firstIndex(of: "]") {
            host = String(authority[authority.index(after: authority.startIndex)..<close])
            let trailing = authority[authority.index(after: close)...]
            if trailing.hasPrefix(":"), let parsed = Int(trailing.dropFirst()) { port = parsed }
        } else if let colon = authority.lastIndex(of: ":") {
            let portText = authority[authority.index(after: colon)...]
            if let parsed = Int(portText) {
                host = String(authority[..<colon])
                port = parsed
            }
        }
        return (host, port)
    }

    nonisolated static func splitPathQuery(_ target: String) -> (path: String, query: String?) {
        guard let mark = target.firstIndex(of: "?") else {
            return (target.isEmpty ? "/" : target, nil)
        }
        let path = String(target[..<mark])
        let query = String(target[target.index(after: mark)...])
        return (path.isEmpty ? "/" : path, query.isEmpty ? nil : query)
    }
}

private extension String {
    nonisolated var beforeSemicolon: String {
        split(separator: ";").first.map(String.init) ?? self
    }
}

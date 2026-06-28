import Foundation
import SwiftMITM
import os

private let logger = Logger(subsystem: "corelift.api-ghost", category: "ProxyCaptureSink")

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

    private let lock = NSLock()
    private var pending: [UUID: Pending] = [:]

    func receive(_ event: CaptureEvent) {
        switch event {
        case .requestHead(let head):
            withLock { pending[head.id] = Pending(request: head) }
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
            Task { @MainActor in Self.store(record) }
        case let .streamError(requestID, message):
            withLock { _ = pending.removeValue(forKey: requestID) }
            logger.debug("Proxy stream error \(requestID): \(message)")
        }
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }
}

// MARK: - Finalization (JS-mode parity)

private extension ProxyCaptureSink {
    @MainActor
    static func store(_ record: Pending) {
        guard TrafficCapture.shared.isCapturing else { return }

        let resolved = Resolved(record)
        let decision = NoiseFilter.shared.shouldCapture(
            host: resolved.host,
            path: resolved.path,
            contentType: resolved.contentType,
            responseSize: record.responseBodyBytes
        )
        guard decision.shouldCapture else {
            TrafficCapture.shared.recordFiltered()
            return
        }
        TrafficCapture.shared.store(makeCapture(record: record, resolved: resolved))
    }

    /// Fields derived once from the engine heads — the bridge from `CaptureEvent` semantics to the `Capture` row.
    struct Resolved {
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

    @MainActor
    static func makeCapture(record: Pending, resolved: Resolved) -> Capture {
        let head = record.request
        let isWebSocket = isWebSocket(requestHeaders: resolved.requestHeaders, status: record.response?.status)
        let requestBody = decodedBody(
            record.requestBody,
            headers: resolved.requestHeaders,
            truncated: record.requestTruncated
        )
        let responseBody = decodedBody(
            record.responseBody,
            headers: resolved.responseHeaders ?? [:],
            truncated: record.responseTruncated
        )
        let url = buildURL(scheme: head.scheme, resolved: resolved)
        let requestContentType = headerValue(resolved.requestHeaders, "content-type")
        let graphql = url.flatMap {
            GraphQLParser.parse(method: head.method, url: $0, contentType: requestContentType, body: requestBody)
        }

        return Capture(
            sessionId: TrafficCapture.shared.sessionId,
            method: head.method,
            scheme: head.scheme,
            host: resolved.host,
            port: resolved.port,
            path: resolved.path,
            query: resolved.query,
            requestHeaders: resolved.requestHeaders.toJSONString(),
            requestBody: requestBody,
            requestBodySize: record.requestBodyBytes,
            statusCode: record.response?.status,
            statusMessage: nil,
            responseHeaders: resolved.responseHeaders.flatMap { $0.toJSONString() },
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
    static func decodedBody(_ body: Data, headers: [String: String], truncated: Bool) -> Data? {
        guard !body.isEmpty else { return nil }
        let encoding = headerValue(headers, "content-encoding")
        let decoded = HTTPBodyDecoder.decode(body, contentEncoding: encoding, truncated: truncated)
        return decoded.isEmpty ? nil : decoded
    }

    static func buildURL(scheme: String, resolved: Resolved) -> URL? {
        var components = URLComponents()
        components.scheme = scheme
        components.host = resolved.host
        components.port = resolved.port
        components.path = resolved.path
        components.percentEncodedQuery = resolved.query
        return components.url
    }

    /// Covers WS-over-HTTP/1.1 (Upgrade handshake / 101). WS-over-h2 (RFC 8441) is not proxied — capture it in JS-injection mode.
    static func isWebSocket(requestHeaders: [String: String], status: Int?) -> Bool {
        if status == 101 { return true }
        return headerValue(requestHeaders, "upgrade")?.lowercased().contains("websocket") ?? false
    }

    static func dictionary(_ fields: [HTTPHeaderField]) -> [String: String] {
        var dict: [String: String] = [:]
        for field in fields { dict[field.name] = field.value }
        return dict
    }

    static func headerValue(_ headers: [String: String], _ name: String) -> String? {
        let target = name.lowercased()
        for (key, value) in headers where key.lowercased() == target { return value }
        return nil
    }

    static func splitAuthority(_ authority: String, scheme: String) -> (host: String, port: Int?) {
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

    static func splitPathQuery(_ target: String) -> (path: String, query: String?) {
        guard let mark = target.firstIndex(of: "?") else {
            return (target.isEmpty ? "/" : target, nil)
        }
        let path = String(target[..<mark])
        let query = String(target[target.index(after: mark)...])
        return (path.isEmpty ? "/" : path, query.isEmpty ? nil : query)
    }
}

private extension String {
    var beforeSemicolon: String {
        split(separator: ";").first.map(String.init) ?? self
    }
}

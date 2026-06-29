import Foundation
import os
import WebKit

private let logger = Logger(subsystem: "corelift.api-ghost", category: "JSMessageHandler")

final class JSMessageHandler: NSObject, WKScriptMessageHandler {
    static let handlerName = "apiGhost"

    /// Set per-tab by the Browser so captures are attributed to their source tab; nil in single-view mode.
    var sourceTabId: String?

    var pendingRequests: [String: PendingRequest] = [:]

    var activeConnections: [String: ConnectionState] = [:]

    var messageSequence: [String: Int] = [:]

    private let lock = NSLock()

    // MARK: - Types

    struct PendingRequest {
        let url: String
        let method: String
        let headers: [String: String]
        let body: String?
        let timestamp: Date
        let isBeacon: Bool
        let uuid: String
    }

    struct ConnectionState {
        var connection: RealtimeConnection
        var messagesSent: Int = 0
        var messagesReceived: Int = 0
        var bytesSent: Int = 0
        var bytesReceived: Int = 0
    }

    func withLock(_ block: () -> Void) {
        lock.lock()
        block()
        lock.unlock()
    }

    // MARK: - WKScriptMessageHandler

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        guard let dict = message.body as? [String: Any],
              let type = dict["type"] as? String else {
            logger.warning("Invalid message format")
            return
        }

        switch type {
        case "request":
            handleRequest(dict: dict)
        case "response":
            handleResponse(dict: dict)
        case "error":
            handleError(dict: dict)
        case "stream_chunk":
            handleStreamChunk(dict: dict)
        case "websocket":
            handleWebSocket(dict: dict)
        case "sse", "sse_connect":
            handleSSE(dict: dict)
        default:
            logger.warning("Unknown message type: \(type)")
        }
    }

    // MARK: - HTTP Request Handling

    private func handleRequest(dict: [String: Any]) {
        guard let id = dict["id"] as? String else { return }

        let url = dict["url"] as? String ?? ""
        let method = dict["method"] as? String ?? "GET"
        let headers = dict["headers"] as? [String: String] ?? [:]
        let body = dict["body"] as? String
        let rawTimestamp = dict["timestamp"] as? Double
            ?? Date().timeIntervalSince1970 * 1000
        let timestamp = Date(timeIntervalSince1970: rawTimestamp / 1000)
        let isBeacon = dict["isBeacon"] as? Bool ?? false

        logger.debug("Request: \(method) \(url)")

        withLock {
            pendingRequests[id] = PendingRequest(
                url: url,
                method: method,
                headers: headers,
                body: body,
                timestamp: timestamp,
                isBeacon: isBeacon,
                uuid: UUID().uuidString
            )
        }
    }

    // MARK: - HTTP Response Handling

    private func handleResponse(dict: [String: Any]) {
        guard let id = dict["id"] as? String else { return }

        var request: PendingRequest?
        withLock { request = pendingRequests.removeValue(forKey: id) }

        guard let request = request else {
            logger.debug("No pending request for id: \(id)")
            return
        }

        let responseData = parseResponseData(from: dict)

        logger.debug("Response: \(responseData.status ?? 0) for \(request.method) \(request.url)")

        guard let urlComponents = URLComponents(string: request.url) else {
            logger.error("Failed to parse URL: \(request.url)")
            return
        }

        createAndStoreCapture(
            request: request,
            responseData: responseData,
            urlComponents: urlComponents
        )
    }

    private func parseResponseData(from dict: [String: Any]) -> ResponseData {
        ResponseData(
            status: dict["status"] as? Int,
            statusText: dict["statusText"] as? String,
            headers: dict["headers"] as? [String: String] ?? [:],
            body: dict["body"] as? String,
            duration: dict["duration"] as? Int,
            isStreaming: dict["isStreaming"] as? Bool ?? false
        )
    }

    private func createAndStoreCapture(
        request: PendingRequest,
        responseData: ResponseData,
        urlComponents: URLComponents
    ) {
        let host = urlComponents.host ?? ""
        let path = urlComponents.path.isEmpty ? "/" : urlComponents.path
        let scheme = urlComponents.scheme ?? "https"
        let port = urlComponents.port ?? (scheme == "https" ? 443 : 80)
        let contentType = responseData.headers["content-type"]
            ?? responseData.headers["Content-Type"]

        let filterResult = NoiseFilter.shared.shouldCapture(
            host: host,
            path: path,
            contentType: contentType,
            responseSize: responseData.body?.count ?? 0
        )

        guard TrafficCapture.shared.isCapturing else { return }

        if !filterResult.shouldCapture {
            TrafficCapture.shared.recordFiltered()
            logger.debug("Filtered: \(host)\(path)")
            return
        }

        let trafficType = request.isBeacon ? "beacon"
            : responseData.isStreaming ? "streaming" : "http"

        let graphql = graphQLInfo(request: request, urlComponents: urlComponents)

        let parameters = CaptureParameters(
            scheme: scheme,
            host: host,
            port: port,
            method: request.method,
            path: path,
            query: urlComponents.query,
            requestHeaders: request.headers,
            requestBody: request.body?.data(using: .utf8),
            statusCode: responseData.status,
            statusMessage: responseData.statusText,
            responseHeaders: responseData.headers,
            responseBody: responseData.body?.data(using: .utf8),
            contentType: contentType,
            durationMs: responseData.duration,
            graphqlOperationName: graphql?.operationName,
            graphqlOperationType: graphql?.storedOperationType,
            sourceTabId: sourceTabId
        )
        let capture = TrafficCapture.shared.createCapture(from: parameters)

        TrafficCapture.shared.store(capture)
        logger.info("Captured: \(request.method) \(host)\(path) -> \(responseData.status ?? 0) [\(trafficType)]")
    }

    private func graphQLInfo(request: PendingRequest, urlComponents: URLComponents) -> GraphQLOperationInfo? {
        guard let url = urlComponents.url ?? URL(string: request.url) else { return nil }
        let contentType = request.headers.first { $0.key.lowercased() == "content-type" }?.value
        return GraphQLParser.parse(
            method: request.method,
            url: url,
            contentType: contentType,
            body: request.body?.data(using: .utf8)
        )
    }

    // MARK: - Error Handling

    private func handleError(dict: [String: Any]) {
        guard let id = dict["id"] as? String else { return }

        var request: PendingRequest?
        withLock { request = pendingRequests.removeValue(forKey: id) }

        let errorMessage = dict["error"] as? String ?? "Unknown error"
        logger.error("Error for \(request?.url ?? id): \(errorMessage)")
    }

    // MARK: - Stream Chunk Handling

    private func handleStreamChunk(dict: [String: Any]) {
        guard TrafficCapture.shared.isCapturing else { return }

        guard let id = dict["id"] as? String,
              let chunk = dict["chunk"] as? String else { return }

        let chunkIndex = dict["chunkIndex"] as? Int ?? -1

        var captureUUID = id
        withLock { captureUUID = pendingRequests[id]?.uuid ?? id }

        let streamChunk = StreamChunk.fromText(
            captureUUID: captureUUID,
            sessionId: TrafficCapture.shared.sessionId,
            chunkIndex: chunkIndex,
            text: chunk
        )

        Task {
            do {
                try RealtimeStore.shared.saveStreamChunk(streamChunk)
            } catch {
                logger.error("Failed to save stream chunk: \(error)")
            }
        }
    }

    // MARK: - Connection Utilities

    var activeConnectionCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return activeConnections.count
    }

    var activeConnectionIds: [String] {
        lock.lock()
        defer { lock.unlock() }
        return Array(activeConnections.keys)
    }

    func reset() {
        withLock {
            pendingRequests.removeAll()
            activeConnections.removeAll()
            messageSequence.removeAll()
        }
    }
}

// MARK: - Response Data

struct ResponseData {
    let status: Int?
    let statusText: String?
    let headers: [String: String]
    let body: String?
    let duration: Int?
    let isStreaming: Bool
}

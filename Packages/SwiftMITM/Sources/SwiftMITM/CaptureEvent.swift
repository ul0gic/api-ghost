import Foundation

public enum HTTPProtocolVersion: String, Sendable {
    case http11 = "HTTP/1.1"
    case http2 = "HTTP/2"
}

public struct HTTPHeaderField: Sendable, Hashable {
    public let name: String
    public let value: String

    public init(name: String, value: String) {
        self.name = name
        self.value = value
    }
}

public struct CapturedRequestHead: Sendable {
    public let id: UUID
    public let timestamp: Date
    public let scheme: String
    public let authority: String
    public let method: String
    public let path: String
    public let version: HTTPProtocolVersion
    public let headers: [HTTPHeaderField]

    public init(
        id: UUID,
        timestamp: Date,
        scheme: String,
        authority: String,
        method: String,
        path: String,
        version: HTTPProtocolVersion,
        headers: [HTTPHeaderField]
    ) {
        self.id = id
        self.timestamp = timestamp
        self.scheme = scheme
        self.authority = authority
        self.method = method
        self.path = path
        self.version = version
        self.headers = headers
    }
}

public struct CapturedResponseHead: Sendable {
    public let requestID: UUID
    public let timestamp: Date
    public let status: Int
    public let version: HTTPProtocolVersion
    public let headers: [HTTPHeaderField]

    public init(
        requestID: UUID,
        timestamp: Date,
        status: Int,
        version: HTTPProtocolVersion,
        headers: [HTTPHeaderField]
    ) {
        self.requestID = requestID
        self.timestamp = timestamp
        self.status = status
        self.version = version
        self.headers = headers
    }
}

public enum CaptureEvent: Sendable {
    case requestHead(CapturedRequestHead)
    /// `bytes` is the captured (bounded) slice of this chunk; `byteCount` is the chunk's full size.
    case requestBodyChunk(requestID: UUID, bytes: [UInt8], byteCount: Int)
    /// `truncated` is true when the full body exceeded the capture limit, so `bytes` are partial.
    case requestEnd(requestID: UUID, truncated: Bool)
    case responseHead(CapturedResponseHead)
    /// `bytes` is the captured (bounded) slice of this chunk; `byteCount` is the chunk's full size.
    case responseBodyChunk(requestID: UUID, bytes: [UInt8], byteCount: Int)
    /// `truncated` is true when the full body exceeded the capture limit, so `bytes` are partial.
    case responseEnd(requestID: UUID, truncated: Bool)
    case streamError(requestID: UUID, message: String)
}

public protocol CaptureEventSink: Sendable {
    func receive(_ event: CaptureEvent)
}

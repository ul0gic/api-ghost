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
    case requestBodyChunk(requestID: UUID, byteCount: Int)
    case requestEnd(requestID: UUID)
    case responseHead(CapturedResponseHead)
    case responseBodyChunk(requestID: UUID, byteCount: Int)
    case responseEnd(requestID: UUID)
    case streamError(requestID: UUID, message: String)
}

public protocol CaptureEventSink: Sendable {
    func receive(_ event: CaptureEvent)
}

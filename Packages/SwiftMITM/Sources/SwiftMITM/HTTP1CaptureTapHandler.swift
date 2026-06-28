import Foundation
import NIOCore

final class HTTP1CaptureTapHandler: ChannelInboundHandler {
    typealias InboundIn = ByteBuffer
    typealias InboundOut = ByteBuffer

    enum Direction {
        case request
        case response
    }

    private let direction: Direction
    private let authority: String
    private let correlator: HTTP1ExchangeCorrelator
    private let sink: CaptureEventSink
    private let parser: HTTP1MessageParser
    private let captureBodyLimit: Int
    private var currentID: UUID?
    private var bodyBuffer: CaptureBodyBuffer

    init(
        direction: Direction,
        authority: String,
        correlator: HTTP1ExchangeCorrelator,
        sink: CaptureEventSink,
        captureBodyLimit: Int = 0
    ) {
        self.direction = direction
        self.authority = authority
        self.correlator = correlator
        self.sink = sink
        self.captureBodyLimit = captureBodyLimit
        self.parser = HTTP1MessageParser(mode: direction == .request ? .request : .response)
        self.bodyBuffer = CaptureBodyBuffer(limit: captureBodyLimit)
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let buffer = unwrapInboundIn(data)
        parser.feed(
            buffer.readableBytesView,
            methodProvider: { [self] in
                let exchange = correlator.dequeue()
                currentID = exchange?.id
                return exchange?.method
            },
            emit: { [self] output in handle(output) },
            bodyBytes: { [self] chunk in captureBody(chunk) }
        )
        context.fireChannelRead(data)
    }

    func channelInactive(context: ChannelHandlerContext) {
        parser.finish { [self] output in handle(output) }
        context.fireChannelInactive()
    }

    private func handle(_ output: HTTP1ParserOutput) {
        switch output {
        case let .requestHead(method, path, headers):
            let id = UUID()
            currentID = id
            bodyBuffer = CaptureBodyBuffer(limit: captureBodyLimit)
            correlator.enqueue(id: id, method: method)
            let host = headers.first { $0.name.lowercased() == "host" }?.value ?? authority
            sink.receive(
                .requestHead(
                    CapturedRequestHead(
                        id: id,
                        timestamp: Date(),
                        scheme: "https",
                        authority: host,
                        method: method,
                        path: path,
                        version: .http11,
                        headers: headers
                    )
                )
            )
        case let .responseHead(status, headers):
            let id = currentID ?? UUID()
            currentID = id
            bodyBuffer = CaptureBodyBuffer(limit: captureBodyLimit)
            sink.receive(
                .responseHead(
                    CapturedResponseHead(
                        requestID: id,
                        timestamp: Date(),
                        status: status,
                        version: .http11,
                        headers: headers
                    )
                )
            )
        case .bodyChunk:
            break // body bytes are emitted via captureBody(_:) on the bodyBytes path
        case .messageComplete:
            guard let id = currentID else { return }
            let truncated = bodyBuffer.truncated
            sink.receive(
                direction == .request
                    ? .requestEnd(requestID: id, truncated: truncated)
                    : .responseEnd(requestID: id, truncated: truncated)
            )
            currentID = nil
        case .failed:
            break
        }
    }

    private func captureBody<Bytes: Collection>(_ chunk: Bytes) where Bytes.Element == UInt8 {
        guard let id = currentID else { return }
        let fullSize = chunk.count
        let bytes = bodyBuffer.take(chunk)
        sink.receive(
            direction == .request
                ? .requestBodyChunk(requestID: id, bytes: bytes, byteCount: fullSize)
                : .responseBodyChunk(requestID: id, bytes: bytes, byteCount: fullSize)
        )
    }
}

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
    private var currentID: UUID?

    init(direction: Direction, authority: String, correlator: HTTP1ExchangeCorrelator, sink: CaptureEventSink) {
        self.direction = direction
        self.authority = authority
        self.correlator = correlator
        self.sink = sink
        self.parser = HTTP1MessageParser(mode: direction == .request ? .request : .response)
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
            emit: { [self] output in handle(output) }
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
        case .bodyChunk(let byteCount):
            guard let id = currentID else { return }
            sink.receive(
                direction == .request
                    ? .requestBodyChunk(requestID: id, byteCount: byteCount)
                    : .responseBodyChunk(requestID: id, byteCount: byteCount)
            )
        case .messageComplete:
            guard let id = currentID else { return }
            sink.receive(direction == .request ? .requestEnd(requestID: id) : .responseEnd(requestID: id))
            currentID = nil
        case .failed:
            break
        }
    }
}

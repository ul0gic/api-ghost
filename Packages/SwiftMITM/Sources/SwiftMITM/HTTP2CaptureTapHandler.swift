import Foundation
import NIOCore
import NIOHPACK
import NIOHTTP2

/// Passes HTTP/2 frame payloads through untouched while emitting capture events. Reports DATA-frame
/// sizes only (never accumulates bodies) so the capture path cannot itself become an unbounded buffer.
final class HTTP2CaptureTapHandler: ChannelInboundHandler {
    typealias InboundIn = HTTP2Frame.FramePayload
    typealias InboundOut = HTTP2Frame.FramePayload

    enum Direction {
        case request
        case response
    }

    private let direction: Direction
    private let requestID: UUID
    private let authority: String
    private let sink: CaptureEventSink

    init(direction: Direction, requestID: UUID, authority: String, sink: CaptureEventSink) {
        self.direction = direction
        self.requestID = requestID
        self.authority = authority
        self.sink = sink
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let payload = unwrapInboundIn(data)
        switch payload {
        case .headers(let frame):
            emitHead(frame.headers)
            if frame.endStream {
                emitEnd()
            }
        case .data(let frame):
            sink.receive(directionalBodyChunk(byteCount: frame.data.readableBytes))
            if frame.endStream {
                emitEnd()
            }
        default:
            break
        }
        context.fireChannelRead(data)
    }

    private func emitHead(_ headers: HPACKHeaders) {
        let fields = headers.compactMap { name, value, _ -> HTTPHeaderField? in
            name.hasPrefix(":") ? nil : HTTPHeaderField(name: name, value: value)
        }
        switch direction {
        case .request:
            let head = CapturedRequestHead(
                id: requestID,
                timestamp: Date(),
                scheme: headers.first(name: ":scheme") ?? "https",
                authority: headers.first(name: ":authority") ?? authority,
                method: headers.first(name: ":method") ?? "",
                path: headers.first(name: ":path") ?? "",
                version: .http2,
                headers: fields
            )
            sink.receive(.requestHead(head))
        case .response:
            let status = headers.first(name: ":status").flatMap(Int.init) ?? 0
            let head = CapturedResponseHead(
                requestID: requestID,
                timestamp: Date(),
                status: status,
                version: .http2,
                headers: fields
            )
            sink.receive(.responseHead(head))
        }
    }

    private func directionalBodyChunk(byteCount: Int) -> CaptureEvent {
        switch direction {
        case .request: return .requestBodyChunk(requestID: requestID, byteCount: byteCount)
        case .response: return .responseBodyChunk(requestID: requestID, byteCount: byteCount)
        }
    }

    private func emitEnd() {
        switch direction {
        case .request: sink.receive(.requestEnd(requestID: requestID))
        case .response: sink.receive(.responseEnd(requestID: requestID))
        }
    }
}

import NIOCore

/// Bidirectional backpressure bridge between two channels (a "matched pair"), reimplemented from
/// Apple's swift-nio-examples connect-proxy. The load-bearing invariant: `read(context:)` is only
/// forwarded to the transport while the *partner* channel is writable — so a slow partner stalls
/// reads on this side instead of buffering unboundedly. At the h2-stream-child level this is what
/// couples one proxy leg's flow-control window to the other's.
///
/// Both partners MUST live on the same EventLoop — the handler calls into the partner's context
/// directly with no loop hop.
final class GlueHandler {
    private var partner: GlueHandler?
    private var context: ChannelHandlerContext?
    private var pendingRead = false

    private init() {}

    static func matchedPair() -> (GlueHandler, GlueHandler) {
        let first = GlueHandler()
        let second = GlueHandler()
        first.partner = second
        second.partner = first
        return (first, second)
    }
}

extension GlueHandler {
    private func partnerWrite(_ data: NIOAny) {
        context?.write(data, promise: nil)
    }

    private func partnerFlush() {
        context?.flush()
    }

    private func partnerWriteEOF() {
        context?.close(mode: .output, promise: nil)
    }

    private func partnerCloseFull() {
        context?.close(promise: nil)
    }

    private func partnerFlushOnly() {
        // Clean close path. For HTTP/2 the terminal END_STREAM is carried in-band by the forwarded
        // frames, so the partner stream closes itself once its writes drain. Forcing any close here —
        // even output-only — truncates the last in-flight frame (observed as a spurious CANCEL one
        // byte before the end). Abnormal termination is handled by errorCaught instead.
        context?.flush()
    }

    private func partnerBecameWritable() {
        if pendingRead {
            pendingRead = false
            context?.read()
        }
    }

    private var partnerWritable: Bool {
        context?.channel.isWritable ?? false
    }
}

extension GlueHandler: ChannelDuplexHandler {
    typealias InboundIn = NIOAny
    typealias InboundOut = NIOAny
    typealias OutboundIn = NIOAny
    typealias OutboundOut = NIOAny

    func handlerAdded(context: ChannelHandlerContext) {
        self.context = context
        if context.channel.isActive {
            // Glued onto an already-active channel (the inbound stream): no channelActive will
            // fire, so service a partner read that was parked before this side was wired.
            partner?.partnerBecameWritable()
        }
    }

    func handlerRemoved(context: ChannelHandlerContext) {
        self.context = nil
        self.partner = nil
    }

    func channelActive(context: ChannelHandlerContext) {
        // Becoming active means this side can now accept writes; release any read the partner parked
        // because we were not yet ready. Without this, a read swallowed during wiring never resumes
        // (the partner starts writable, so no writability transition ever fires).
        partner?.partnerBecameWritable()
        context.fireChannelActive()
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        partner?.partnerWrite(data)
    }

    func channelReadComplete(context: ChannelHandlerContext) {
        partner?.partnerFlush()
    }

    func channelInactive(context: ChannelHandlerContext) {
        partner?.partnerFlushOnly()
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        if let event = event as? ChannelEvent, case .inputClosed = event {
            partner?.partnerWriteEOF()
        } else {
            context.fireUserInboundEventTriggered(event)
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        partner?.partnerCloseFull()
    }

    func channelWritabilityChanged(context: ChannelHandlerContext) {
        if context.channel.isWritable {
            partner?.partnerBecameWritable()
        }
    }

    func read(context: ChannelHandlerContext) {
        if let partner, partner.partnerWritable {
            context.read()
        } else {
            pendingRead = true
        }
    }
}

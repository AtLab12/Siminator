import NIOCore

final nonisolated class UpstreamToClientForwardingHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = ByteBuffer

    private enum Reporting {
        static let minimumDelta = 16 * 1024
    }

    private let clientChannel: Channel
    private let requestID: CapturedNetworkRequest.ID
    private let requestEventSink: LocalHTTPProxyServer.RequestEventSink?
    private var byteCounts: CapturedNetworkRequestByteCounts
    private var lastEmittedResponseBytes = 0

    init(
        clientChannel: Channel,
        requestID: CapturedNetworkRequest.ID,
        initialRequestBytes: Int,
        requestEventSink: LocalHTTPProxyServer.RequestEventSink?
    ) {
        self.clientChannel = clientChannel
        self.requestID = requestID
        self.requestEventSink = requestEventSink
        byteCounts = CapturedNetworkRequestByteCounts(requestBytes: initialRequestBytes)
    }

    func channelRead(context _: ChannelHandlerContext, data: NIOAny) {
        let buffer = unwrapInboundIn(data)
        byteCounts.responseBytes += buffer.readableBytes
        emitByteCountsIfNeeded()
        clientChannel.writeAndFlush(buffer, promise: nil)
    }

    func channelInactive(context: ChannelHandlerContext) {
        emitByteCounts()
        clientChannel.close(promise: nil)
        context.fireChannelInactive()
    }

    func errorCaught(context: ChannelHandlerContext, error: Swift.Error) {
        print("Siminator proxy upstream error: \(error)")
        emitByteCounts()
        clientChannel.close(promise: nil)
        context.close(promise: nil)
    }

    private func emitByteCountsIfNeeded() {
        guard byteCounts.responseBytes - lastEmittedResponseBytes >= Reporting.minimumDelta else {
            return
        }

        emitByteCounts()
    }

    private func emitByteCounts() {
        guard let requestEventSink else { return }
        lastEmittedResponseBytes = byteCounts.responseBytes

        let event = CapturedNetworkRequestEvent.byteCountsChanged(
            id: requestID,
            byteCounts: byteCounts
        )

        Task { @MainActor in
            requestEventSink(event)
        }
    }
}

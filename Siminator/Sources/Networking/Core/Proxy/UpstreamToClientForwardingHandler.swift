import Foundation
import NIOCore
import NIOPosix

nonisolated final class UpstreamToClientForwardingHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = ByteBuffer

    private let clientChannel: Channel

    init(clientChannel: Channel) {
        self.clientChannel = clientChannel
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let buffer = unwrapInboundIn(data)
        clientChannel.writeAndFlush(buffer, promise: nil)
    }

    func channelInactive(context: ChannelHandlerContext) {
        clientChannel.close(promise: nil)
        context.fireChannelInactive()
    }

    func errorCaught(context: ChannelHandlerContext, error: Swift.Error) {
        print("Siminator proxy upstream error: \(error)")
        clientChannel.close(promise: nil)
        context.close(promise: nil)
    }
}

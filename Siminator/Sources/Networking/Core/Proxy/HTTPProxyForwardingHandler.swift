import Foundation
import NIOCore
import NIOPosix

nonisolated final class HTTPProxyForwardingHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer

    private enum State {
        case waitingForRequest
        case connecting
        case forwarding
        case closed
    }

    private var state = State.waitingForRequest
    private var pendingInitialBuffer: ByteBuffer?
    private var upstreamChannel: Channel?
    private var currentRequestID: CapturedNetworkRequest.ID?
    private let requestEventSink: LocalHTTPProxyServer.RequestEventSink?

    init(requestEventSink: LocalHTTPProxyServer.RequestEventSink? = nil) {
        self.requestEventSink = requestEventSink
    }

    func channelActive(context: ChannelHandlerContext) {
        print("Siminator proxy accepted connection from \(context.remoteAddress?.description ?? "unknown remote")")
        context.fireChannelActive()
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        var buffer = unwrapInboundIn(data)

        switch state {
        case .waitingForRequest:
            appendInitialBuffer(&buffer, allocator: context.channel.allocator)
            handleInitialRequestIfPossible(context: context)

        case .connecting:
            appendInitialBuffer(&buffer, allocator: context.channel.allocator)

        case .forwarding:
            guard let upstreamChannel else {
                closeBoth(context: context)
                return
            }

            upstreamChannel.writeAndFlush(buffer, promise: nil)

        case .closed:
            break
        }
    }

    func channelInactive(context: ChannelHandlerContext) {
        upstreamChannel?.close(promise: nil)
        upstreamChannel = nil
        state = .closed
        context.fireChannelInactive()
    }

    func errorCaught(context: ChannelHandlerContext, error: Swift.Error) {
        print("Siminator proxy connection error: \(error)")
        if let currentRequestID {
            emit(.statusChanged(
                id: currentRequestID,
                status: .failed,
                completedAt: Date()
            ))
        }
        closeBoth(context: context)
    }

    private func appendInitialBuffer(_ buffer: inout ByteBuffer, allocator: ByteBufferAllocator) {
        guard buffer.readableBytes > 0 else {
            return
        }

        if pendingInitialBuffer == nil {
            pendingInitialBuffer = allocator.buffer(capacity: buffer.readableBytes)
        }

        pendingInitialBuffer?.writeBuffer(&buffer)
    }

    private func handleInitialRequestIfPossible(context: ChannelHandlerContext) {
        guard let initialBuffer = pendingInitialBuffer,
              let request = HTTPProxyInitialRequest(buffer: initialBuffer) else {
            return
        }

        state = .connecting
        pendingInitialBuffer = nil

        let bootstrap = ClientBootstrap(group: context.eventLoop)
            .channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .channelInitializer { upstreamChannel in
                upstreamChannel.pipeline.addHandler(UpstreamToClientForwardingHandler(clientChannel: context.channel))
            }

        let requestID = UUID()
        currentRequestID = requestID
        emit(.started(CapturedNetworkRequest(
            id: requestID,
            createdAt: Date(),
            completedAt: nil,
            method: request.method,
            host: request.host,
            port: request.port,
            path: request.displayPath,
            status: .inProgress,
            process: .unknown
        )))

        bootstrap.connect(host: request.host, port: request.port).whenComplete { [weak self] result in
            guard let self else {
                return
            }

            switch result {
            case let .success(upstreamChannel):
                self.upstreamChannel = upstreamChannel
                self.state = .forwarding
                self.emit(.statusChanged(
                    id: requestID,
                    status: .succeeded,
                    completedAt: Date()
                ))

                if request.isConnect {
                    print("Siminator proxy CONNECT \(request.host):\(request.port)")
                    let response = context.channel.allocator.buffer(
                        string: "HTTP/1.1 200 Connection Established\r\n\r\n"
                    )
                    context.writeAndFlush(self.wrapOutboundOut(response), promise: nil)

                    let tunneledBytes = request.tunneledBodyBuffer(allocator: context.channel.allocator)
                    if tunneledBytes.readableBytes > 0 {
                        upstreamChannel.writeAndFlush(tunneledBytes, promise: nil)
                    }
                } else {
                    print("Siminator proxy HTTP \(request.method) \(request.host):\(request.port) \(request.displayPath)")
                    let forwardedRequest = request.forwardedBuffer(allocator: context.channel.allocator)
                    upstreamChannel.writeAndFlush(forwardedRequest, promise: nil)
                }

            case let .failure(error):
                print("Siminator proxy failed to connect to \(request.host):\(request.port): \(error)")
                self.emit(.statusChanged(
                    id: requestID,
                    status: .failed,
                    completedAt: Date()
                ))
                self.writeBadGatewayAndClose(context: context)
            }
        }
    }

    private func writeBadGatewayAndClose(context: ChannelHandlerContext) {
        let response = context.channel.allocator.buffer(
            string: "HTTP/1.1 502 Bad Gateway\r\nConnection: close\r\n\r\n"
        )
        context.writeAndFlush(wrapOutboundOut(response)).whenComplete { _ in
            self.closeBoth(context: context)
        }
    }

    private func emit(_ event: CapturedNetworkRequestEvent) {
        guard let requestEventSink else { return }

        Task { @MainActor in
            requestEventSink(event)
        }
    }

    private func closeBoth(context: ChannelHandlerContext) {
        guard state != .closed else {
            return
        }

        state = .closed
        upstreamChannel?.close(promise: nil)
        upstreamChannel = nil
        context.close(promise: nil)
    }
}

import Foundation
import NIOCore
import NIOHTTP1
import NIOPosix
import NIOSSL

final nonisolated class HTTPProxyForwardingHandler: ChannelInboundHandler, RemovableChannelHandler, @unchecked Sendable {
    typealias InboundIn = ByteBuffer
    typealias OutboundOut = ByteBuffer

    private enum State {
        case waitingForRequest
        case connecting
        case preparingMITM
        case forwarding
        case closed
    }

    private var state = State.waitingForRequest
    private var pendingInitialBuffer: ByteBuffer?
    private var upstreamChannel: Channel?
    private var currentRequestID: CapturedNetworkRequest.ID?
    private var resolvedProcess: CapturedRequestProcess?
    private var pendingTLSBuffer: ByteBuffer?
    private var mitmSetupStarted = false
    private let certificateMaterialManager: CertificateMaterialManager
    private let upstreamTLSContext: NIOSSLContext
    private let requestEventSink: LocalHTTPProxyServer.RequestEventSink?

    init(
        certificateMaterialManager: CertificateMaterialManager,
        upstreamTLSContext: NIOSSLContext,
        requestEventSink: LocalHTTPProxyServer.RequestEventSink? = nil
    ) {
        self.certificateMaterialManager = certificateMaterialManager
        self.upstreamTLSContext = upstreamTLSContext
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

        case .preparingMITM:
            appendPendingTLSBuffer(&buffer, allocator: context.channel.allocator)

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

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        guard let resolvedEvent = event as? ResolvedProcessEvent else {
            context.fireUserInboundEventTriggered(event)
            return
        }

        resolvedProcess = resolvedEvent.process

        if let currentRequestID {
            emit(.processResolved(id: currentRequestID, process: resolvedEvent.process))
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
                status: .failed
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
              let request = HTTPProxyInitialRequest(buffer: initialBuffer)
        else {
            return
        }

        state = .connecting
        pendingInitialBuffer = nil

        if request.isConnect {
            prepareMITMConnection(context: context, request: request)
            return
        }

        let bootstrap = ClientBootstrap(group: context.eventLoop)
            .channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .channelInitializer { upstreamChannel in
                upstreamChannel.pipeline.addHandler(UpstreamToClientForwardingHandler(clientChannel: context.channel))
            }

        let requestID = UUID()
        currentRequestID = requestID
        emit(.started(CapturedNetworkRequest(
            id: requestID,
            method: request.method,
            scheme: "http",
            host: request.host,
            port: request.port,
            path: request.displayPath,
            status: .inProgress,
            process: resolvedProcess ?? .unknown
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
                    status: .succeeded
                ))

                print("Siminator proxy HTTP \(request.method) \(request.host):\(request.port) \(request.displayPath)")
                let forwardedRequest = request.forwardedBuffer(allocator: context.channel.allocator)
                upstreamChannel.writeAndFlush(forwardedRequest, promise: nil)

            case let .failure(error):
                print("Siminator proxy failed to connect to \(request.host):\(request.port): \(error)")
                self.emit(.statusChanged(
                    id: requestID,
                    status: .failed
                ))
                self.writeBadGatewayAndClose(context: context)
            }
        }
    }

    private func appendPendingTLSBuffer(_ buffer: inout ByteBuffer, allocator: ByteBufferAllocator) {
        guard buffer.readableBytes > 0 else {
            return
        }

        if pendingTLSBuffer == nil {
            pendingTLSBuffer = allocator.buffer(capacity: buffer.readableBytes)
        }

        pendingTLSBuffer?.writeBuffer(&buffer)
    }

    private func prepareMITMConnection(context: ChannelHandlerContext, request: HTTPProxyInitialRequest) {
        state = .preparingMITM
        let tunneledBytes = request.tunneledBodyBuffer(allocator: context.channel.allocator)
        var mutableTunneledBytes = tunneledBytes
        appendPendingTLSBuffer(&mutableTunneledBytes, allocator: context.channel.allocator)

        let response = context.channel.allocator.buffer(
            string: "HTTP/1.1 200 Connection Established\r\n\r\n"
        )

        context.writeAndFlush(wrapOutboundOut(response)).whenComplete { [weak self] result in
            guard let self else { return }

            switch result {
            case .success:
                self.startMITMSetupIfNeeded(
                    channel: context.channel,
                    host: request.host,
                    port: request.port
                )
            case let .failure(error):
                print("Siminator proxy failed to establish CONNECT tunnel: \(error)")
                self.closeBoth(context: context)
            }
        }
    }

    private func startMITMSetupIfNeeded(channel: Channel, host: String, port: Int) {
        guard !mitmSetupStarted else { return }
        mitmSetupStarted = true

        let certificateMaterialManager = certificateMaterialManager
        Task {
            do {
                let serverTLSContext = try await certificateMaterialManager.serverTLSContext(for: host)

                channel.eventLoop.execute { [weak self] in
                    self?.installMITMPipeline(
                        channel: channel,
                        serverTLSContext: serverTLSContext,
                        host: host,
                        port: port
                    )
                }
            } catch {
                channel.eventLoop.execute { [weak self] in
                    self?.failMITMSetup(channel: channel, error: error)
                }
            }
        }
    }

    private func installMITMPipeline(
        channel: Channel,
        serverTLSContext: NIOSSLContext,
        host: String,
        port: Int
    ) {
        do {
            let tlsHandler = NIOSSLServerHandler(context: serverTLSContext)
            let mitmHandler = HTTPSMITMRequestHandler(
                destinationHost: host,
                destinationPort: port,
                upstreamTLSContext: upstreamTLSContext,
                initialProcess: resolvedProcess ?? .unknown,
                requestEventSink: requestEventSink
            )

            try channel.pipeline.syncOperations.addHandlers(
                [
                    tlsHandler,
                    HTTPResponseEncoder(),
                    ByteToMessageHandler(HTTPRequestDecoder()),
                    mitmHandler,
                ],
                position: .after(self)
            )

            let pendingTLSBuffer = pendingTLSBuffer
            self.pendingTLSBuffer = nil

            try channel.pipeline.syncOperations.removeHandler(self)

            if let pendingTLSBuffer, pendingTLSBuffer.readableBytes > 0 {
                channel.pipeline.fireChannelRead(NIOAny(pendingTLSBuffer))
            }
        } catch {
            failMITMSetup(channel: channel, error: error)
        }
    }

    private func failMITMSetup(channel: Channel, error: Swift.Error) {
        print("Siminator proxy failed to prepare HTTPS MITM: \(error)")
        state = .closed
        channel.close(promise: nil)
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

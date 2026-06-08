import Foundation
import NIOCore
import NIOPosix

nonisolated enum ProxyConstants {
    static let host = "127.0.0.1"
    static let port = 9090
}

actor LocalHTTPProxyServer {
    typealias RequestEventSink = @MainActor @Sendable (CapturedNetworkRequestEvent) -> Void

    private let requestEventSink: RequestEventSink?
    private var channel: Channel?
    private var eventLoopGroup: MultiThreadedEventLoopGroup?

    init(requestEventSink: RequestEventSink? = nil) {
        self.requestEventSink = requestEventSink
    }

    var isRunning: Bool {
        channel != nil
    }

    func start(port: Int = ProxyConstants.port) async throws -> Int {
        if channel != nil {
            return port
        }

        let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
        let requestEventSink = requestEventSink
        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                channel.pipeline.addHandler(HTTPProxyForwardingHandler(requestEventSink: requestEventSink))
            }
            .childChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 16)
            .childChannelOption(ChannelOptions.recvAllocator, value: AdaptiveRecvByteBufferAllocator())

        do {
            let channel = try await bootstrap.bind(host: ProxyConstants.host, port: port).get()
            self.channel = channel
            eventLoopGroup = group
            print("Siminator proxy listening on \(channel.localAddress?.description ?? "\(ProxyConstants.host):\(port)")")
            return port
        } catch {
            try await shutdown(group)
            throw error
        }
    }

    func stop() async throws {
        let channel = self.channel
        let group = eventLoopGroup

        self.channel = nil
        eventLoopGroup = nil

        if let channel {
            try await channel.close().get()
        }

        if let group {
            try await shutdown(group)
        }

        print("Siminator proxy stopped")
    }

    private func shutdown(_ group: MultiThreadedEventLoopGroup) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Swift.Error>) in
            group.shutdownGracefully { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        }
    }
}

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

nonisolated private final class UpstreamToClientForwardingHandler: ChannelInboundHandler, @unchecked Sendable {
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

nonisolated private struct HTTPProxyInitialRequest: Sendable {
    let method: String
    let host: String
    let port: Int
    let isConnect: Bool
    let displayPath: String

    private let headerText: String
    private let bodyBytes: [UInt8]

    init?(buffer: ByteBuffer) {
        guard let requestBytes = buffer.getBytes(at: buffer.readerIndex, length: buffer.readableBytes),
              let headerEnd = requestBytes.firstRange(of: [13, 10, 13, 10]) else {
            return nil
        }

        let headerBytes = Array(requestBytes[..<headerEnd.upperBound])
        let remainingBytes = Array(requestBytes[headerEnd.upperBound...])

        guard let headerText = String(bytes: headerBytes, encoding: .utf8) else {
            return nil
        }

        let headerLines = headerText.components(separatedBy: "\r\n")
        guard let firstLine = headerLines.first else {
            return nil
        }

        let requestLineParts = firstLine.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: false)
        guard requestLineParts.count == 3 else {
            return nil
        }

        let method = String(requestLineParts[0])
        let uri = String(requestLineParts[1])
        let isConnect = method.uppercased() == "CONNECT"

        if isConnect {
            guard let destination = HTTPProxyDestination(connectURI: uri) else {
                return nil
            }

            self.method = method
            host = destination.host
            port = destination.port
            self.isConnect = true
            displayPath = uri
            self.headerText = headerText
            bodyBytes = remainingBytes
            return
        }

        guard let destination = HTTPProxyDestination(requestURI: uri, headerLines: headerLines) else {
            return nil
        }

        self.method = method
        host = destination.host
        port = destination.port
        self.isConnect = false
        displayPath = destination.path
        self.headerText = HTTPProxyInitialRequest.rewrittenHeaderText(
            originalHeaderText: headerText,
            originalFirstLine: firstLine,
            method: method,
            path: destination.path,
            version: String(requestLineParts[2])
        )
        bodyBytes = remainingBytes
    }

    func forwardedBuffer(allocator: ByteBufferAllocator) -> ByteBuffer {
        var buffer = allocator.buffer(capacity: headerText.utf8.count + bodyBytes.count)
        buffer.writeString(headerText)
        buffer.writeBytes(bodyBytes)
        return buffer
    }

    func tunneledBodyBuffer(allocator: ByteBufferAllocator) -> ByteBuffer {
        var buffer = allocator.buffer(capacity: bodyBytes.count)
        buffer.writeBytes(bodyBytes)
        return buffer
    }

    private static func rewrittenHeaderText(
        originalHeaderText: String,
        originalFirstLine: String,
        method: String,
        path: String,
        version: String
    ) -> String {
        let rewrittenFirstLine = "\(method) \(path) \(version)"

        guard let firstLineRange = originalHeaderText.range(of: originalFirstLine) else {
            return originalHeaderText
        }

        return originalHeaderText.replacingCharacters(in: firstLineRange, with: rewrittenFirstLine)
    }
}

nonisolated private struct HTTPProxyDestination: Sendable {
    let host: String
    let port: Int
    let path: String

    init?(connectURI: String) {
        let parts = connectURI.split(separator: ":", maxSplits: 1)
        guard let hostPart = parts.first, !hostPart.isEmpty else {
            return nil
        }

        host = String(hostPart)
        port = parts.count == 2 ? Int(parts[1]) ?? 443 : 443
        path = connectURI
    }

    init?(requestURI: String, headerLines: [String]) {
        if let url = URL(string: requestURI), let urlHost = url.host {
            host = urlHost
            port = url.port ?? HTTPProxyDestination.defaultPort(for: url.scheme)
            path = HTTPProxyDestination.originPath(from: url)
            return
        }

        guard let hostHeader = HTTPProxyDestination.headerValue(named: "Host", in: headerLines) else {
            return nil
        }

        let parsedHost = HTTPProxyDestination.parseHostAndPort(hostHeader, defaultPort: 80)
        host = parsedHost.host
        port = parsedHost.port
        path = requestURI.isEmpty ? "/" : requestURI
    }

    private static func defaultPort(for scheme: String?) -> Int {
        scheme?.lowercased() == "https" ? 443 : 80
    }

    private static func originPath(from url: URL) -> String {
        let path = url.path.isEmpty ? "/" : url.path

        if let query = url.query, !query.isEmpty {
            return "\(path)?\(query)"
        }

        return path
    }

    private static func headerValue(named name: String, in headerLines: [String]) -> String? {
        let prefix = "\(name):"

        for line in headerLines.dropFirst() {
            if line.range(of: prefix, options: [.caseInsensitive, .anchored]) != nil {
                return String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        return nil
    }

    private static func parseHostAndPort(_ value: String, defaultPort: Int) -> (host: String, port: Int) {
        let parts = value.split(separator: ":", maxSplits: 1)
        let host = parts.first.map(String.init) ?? value
        let port = parts.count == 2 ? Int(parts[1]) ?? defaultPort : defaultPort
        return (host, port)
    }
}

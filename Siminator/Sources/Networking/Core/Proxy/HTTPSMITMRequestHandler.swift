import Foundation
import NIOCore
import NIOHTTP1
import NIOPosix
import NIOSSL

final nonisolated class HTTPSMITMRequestHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = HTTPServerRequestPart
    typealias OutboundOut = HTTPServerResponsePart

    private let destinationHost: String
    private let destinationPort: Int
    private let upstreamTLSContext: NIOSSLContext
    private let requestEventSink: LocalHTTPProxyServer.RequestEventSink?
    private let requestStatusQueue = HTTPSRequestStatusQueue()
    private var upstreamChannel: Channel?
    private var pendingRequestParts: [HTTPClientRequestPart] = []
    private var recordedRequestIDs: [CapturedNetworkRequest.ID] = []
    private var resolvedProcess: CapturedRequestProcess
    private var isConnecting = false
    private var isClosed = false

    init(
        destinationHost: String,
        destinationPort: Int,
        upstreamTLSContext: NIOSSLContext,
        initialProcess: CapturedRequestProcess,
        requestEventSink: LocalHTTPProxyServer.RequestEventSink?
    ) {
        self.destinationHost = destinationHost
        self.destinationPort = destinationPort
        self.upstreamTLSContext = upstreamTLSContext
        resolvedProcess = initialProcess
        self.requestEventSink = requestEventSink
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        guard !isClosed else { return }

        let requestPart = unwrapInboundIn(data)

        if case let .head(head) = requestPart {
            recordRequest(head)
        }

        let upstreamPart = HTTPClientRequestPart(serverRequestPart: requestPart)

        if let upstreamChannel {
            upstreamChannel.writeAndFlush(upstreamPart, promise: nil)
            return
        }

        pendingRequestParts.append(upstreamPart)
        connectUpstreamIfNeeded(context: context)
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        guard let resolvedEvent = event as? ResolvedProcessEvent else {
            context.fireUserInboundEventTriggered(event)
            return
        }

        resolvedProcess = resolvedEvent.process

        for requestID in recordedRequestIDs {
            emit(.processResolved(id: requestID, process: resolvedEvent.process))
        }
    }

    func channelInactive(context: ChannelHandlerContext) {
        isClosed = true
        upstreamChannel?.close(promise: nil)
        upstreamChannel = nil
        context.fireChannelInactive()
    }

    func errorCaught(context: ChannelHandlerContext, error: Swift.Error) {
        print("Siminator HTTPS MITM client-side error: \(error)")
        failPendingRequests()
        closeBoth(context: context)
    }

    private func connectUpstreamIfNeeded(context: ChannelHandlerContext) {
        guard !isConnecting, upstreamChannel == nil else {
            return
        }

        isConnecting = true

        let bootstrap = ClientBootstrap(group: context.eventLoop)
            .channelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .channelInitializer { [upstreamTLSContext, destinationHost, requestEventSink] upstreamChannel in
                upstreamChannel.eventLoop.makeCompletedFuture {
                    let tlsHandler = try NIOSSLClientHandler(
                        context: upstreamTLSContext,
                        serverHostname: destinationHost
                    )

                    try upstreamChannel.pipeline.syncOperations.addHandler(tlsHandler)
                    try upstreamChannel.pipeline.syncOperations.addHTTPClientHandlers()
                    try upstreamChannel.pipeline.syncOperations.addHandler(UpstreamHTTPResponseForwardingHandler(
                        clientChannel: context.channel,
                        requestStatusQueue: self.requestStatusQueue,
                        requestEventSink: requestEventSink
                    ))
                }
            }

        bootstrap.connect(host: destinationHost, port: destinationPort).whenComplete { [weak self] result in
            guard let self else { return }

            self.isConnecting = false

            switch result {
            case let .success(upstreamChannel):
                self.upstreamChannel = upstreamChannel
                self.flushPendingRequestParts(to: upstreamChannel)

            case let .failure(error):
                print("Siminator HTTPS MITM failed to connect to \(self.destinationHost):\(self.destinationPort): \(error)")
                self.failPendingRequests()
                self.writeBadGatewayAndClose(context: context)
            }
        }
    }

    private func flushPendingRequestParts(to upstreamChannel: Channel) {
        guard !pendingRequestParts.isEmpty else { return }

        for part in pendingRequestParts {
            upstreamChannel.write(part, promise: nil)
        }

        pendingRequestParts.removeAll(keepingCapacity: true)
        upstreamChannel.flush()
    }

    private func recordRequest(_ head: HTTPRequestHead) {
        let requestID = UUID()
        recordedRequestIDs.append(requestID)
        requestStatusQueue.append(requestID)

        emit(.started(CapturedNetworkRequest(
            id: requestID,
            createdAt: Date(),
            completedAt: nil,
            method: head.method.rawValue,
            scheme: "https",
            host: destinationHost,
            port: destinationPort,
            path: head.uri.isEmpty ? "/" : head.uri,
            status: .inProgress,
            process: resolvedProcess
        )))
    }

    private func failPendingRequests() {
        requestStatusQueue.failAll(requestEventSink: requestEventSink)
    }

    private func writeBadGatewayAndClose(context: ChannelHandlerContext) {
        let responseHead = HTTPResponseHead(
            version: .init(major: 1, minor: 1),
            status: .badGateway,
            headers: HTTPHeaders([
                ("Connection", "close"),
                ("Content-Length", "0"),
            ])
        )

        context.write(wrapOutboundOut(.head(responseHead)), promise: nil)
        context.writeAndFlush(wrapOutboundOut(.end(nil))).whenComplete { _ in
            self.closeBoth(context: context)
        }
    }

    private func closeBoth(context: ChannelHandlerContext) {
        guard !isClosed else {
            return
        }

        isClosed = true
        upstreamChannel?.close(promise: nil)
        upstreamChannel = nil
        context.close(promise: nil)
    }

    private func emit(_ event: CapturedNetworkRequestEvent) {
        guard let requestEventSink else { return }

        Task { @MainActor in
            requestEventSink(event)
        }
    }
}

final nonisolated class UpstreamHTTPResponseForwardingHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = HTTPClientResponsePart

    private let clientChannel: Channel
    private let requestStatusQueue: HTTPSRequestStatusQueue
    private let requestEventSink: LocalHTTPProxyServer.RequestEventSink?

    init(
        clientChannel: Channel,
        requestStatusQueue: HTTPSRequestStatusQueue,
        requestEventSink: LocalHTTPProxyServer.RequestEventSink?
    ) {
        self.clientChannel = clientChannel
        self.requestStatusQueue = requestStatusQueue
        self.requestEventSink = requestEventSink
    }

    func channelRead(context _: ChannelHandlerContext, data: NIOAny) {
        let responsePart = unwrapInboundIn(data)

        switch responsePart {
        case let .head(head):
            clientChannel.write(HTTPServerResponsePart.head(head), promise: nil)

        case let .body(buffer):
            clientChannel.write(HTTPServerResponsePart.body(.byteBuffer(buffer)), promise: nil)

        case let .end(headers):
            clientChannel.writeAndFlush(HTTPServerResponsePart.end(headers), promise: nil)
            completeNextRequest()
        }
    }

    func channelInactive(context: ChannelHandlerContext) {
        clientChannel.close(promise: nil)
        context.fireChannelInactive()
    }

    func errorCaught(context: ChannelHandlerContext, error: Swift.Error) {
        print("Siminator HTTPS MITM upstream error: \(error)")
        failWaitingRequests()
        clientChannel.close(promise: nil)
        context.close(promise: nil)
    }

    private func completeNextRequest() {
        requestStatusQueue.completeNext(requestEventSink: requestEventSink)
    }

    private func failWaitingRequests() {
        requestStatusQueue.failAll(requestEventSink: requestEventSink)
    }
}

final nonisolated class HTTPSRequestStatusQueue: @unchecked Sendable {
    private var requestIDsWaitingForResponse: [CapturedNetworkRequest.ID] = []

    func append(_ requestID: CapturedNetworkRequest.ID) {
        requestIDsWaitingForResponse.append(requestID)
    }

    func completeNext(requestEventSink: LocalHTTPProxyServer.RequestEventSink?) {
        guard !requestIDsWaitingForResponse.isEmpty else { return }
        let requestID = requestIDsWaitingForResponse.removeFirst()

        emit(
            .statusChanged(
                id: requestID,
                status: .succeeded,
                completedAt: Date()
            ),
            requestEventSink: requestEventSink
        )
    }

    func failAll(requestEventSink: LocalHTTPProxyServer.RequestEventSink?) {
        let now = Date()

        for requestID in requestIDsWaitingForResponse {
            emit(
                .statusChanged(
                    id: requestID,
                    status: .failed,
                    completedAt: now
                ),
                requestEventSink: requestEventSink
            )
        }

        requestIDsWaitingForResponse.removeAll(keepingCapacity: true)
    }

    private func emit(
        _ event: CapturedNetworkRequestEvent,
        requestEventSink: LocalHTTPProxyServer.RequestEventSink?
    ) {
        guard let requestEventSink else { return }

        Task { @MainActor in
            requestEventSink(event)
        }
    }
}

private extension HTTPClientRequestPart {
    nonisolated init(serverRequestPart: HTTPServerRequestPart) {
        switch serverRequestPart {
        case var .head(head):
            head.uri = HTTPClientRequestPart.originFormURI(from: head.uri)
            head.headers.remove(name: "Proxy-Connection")
            self = .head(head)

        case let .body(buffer):
            self = .body(.byteBuffer(buffer))

        case let .end(headers):
            self = .end(headers)
        }
    }

    private nonisolated static func originFormURI(from uri: String) -> String {
        guard let url = URL(string: uri), url.host != nil else {
            return uri.isEmpty ? "/" : uri
        }

        let path = url.path.isEmpty ? "/" : url.path

        if let query = url.query, !query.isEmpty {
            return "\(path)?\(query)"
        }

        return path
    }
}

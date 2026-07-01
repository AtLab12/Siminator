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
    private var activeRequestID: CapturedNetworkRequest.ID?
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

        switch requestPart {
        case let .head(head):
            recordRequest(head)

        case let .body(buffer):
            if let activeRequestID {
                requestStatusQueue.addRequestBytes(
                    buffer.readableBytes,
                    to: activeRequestID,
                    requestEventSink: requestEventSink
                )
            }

        case let .end(headers):
            if let activeRequestID {
                requestStatusQueue.addRequestBytes(
                    headers.httpHeaderByteCount,
                    to: activeRequestID,
                    requestEventSink: requestEventSink
                )
                requestStatusQueue.finishRequestBytes(
                    for: activeRequestID,
                    requestEventSink: requestEventSink
                )
            }
            activeRequestID = nil
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
        activeRequestID = requestID
        recordedRequestIDs.append(requestID)
        requestStatusQueue.append(
            requestID,
            initialRequestBytes: head.requestHeaderByteCount
        )

        emit(.started(CapturedNetworkRequest(
            id: requestID,
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
            requestStatusQueue.addResponseBytes(
                head.responseHeaderByteCount,
                requestEventSink: requestEventSink
            )
            clientChannel.write(HTTPServerResponsePart.head(head), promise: nil)

        case let .body(buffer):
            requestStatusQueue.addResponseBytes(
                buffer.readableBytes,
                requestEventSink: requestEventSink
            )
            clientChannel.write(HTTPServerResponsePart.body(.byteBuffer(buffer)), promise: nil)

        case let .end(headers):
            requestStatusQueue.addResponseBytes(
                headers.httpHeaderByteCount,
                requestEventSink: requestEventSink
            )
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
    private enum Reporting {
        static let minimumDelta = 16 * 1024
    }

    private struct Entry {
        let id: CapturedNetworkRequest.ID
        var byteCounts: CapturedNetworkRequestByteCounts
        var lastEmittedByteCounts = CapturedNetworkRequestByteCounts()
    }

    private var requestsWaitingForResponse: [Entry] = []

    func append(_ requestID: CapturedNetworkRequest.ID, initialRequestBytes: Int) {
        requestsWaitingForResponse.append(Entry(
            id: requestID,
            byteCounts: CapturedNetworkRequestByteCounts(requestBytes: initialRequestBytes)
        ))
    }

    func addRequestBytes(
        _ byteCount: Int,
        to requestID: CapturedNetworkRequest.ID,
        requestEventSink: LocalHTTPProxyServer.RequestEventSink?
    ) {
        guard byteCount > 0,
              let index = requestsWaitingForResponse.firstIndex(where: { $0.id == requestID })
        else { return }

        requestsWaitingForResponse[index].byteCounts.requestBytes += byteCount
        emitByteCountsIfNeeded(at: index, requestEventSink: requestEventSink)
    }

    func finishRequestBytes(
        for requestID: CapturedNetworkRequest.ID,
        requestEventSink: LocalHTTPProxyServer.RequestEventSink?
    ) {
        guard let index = requestsWaitingForResponse.firstIndex(where: { $0.id == requestID }) else {
            return
        }

        emitByteCounts(at: index, requestEventSink: requestEventSink)
    }

    func addResponseBytes(
        _ byteCount: Int,
        requestEventSink: LocalHTTPProxyServer.RequestEventSink?
    ) {
        guard byteCount > 0, !requestsWaitingForResponse.isEmpty else { return }

        requestsWaitingForResponse[0].byteCounts.responseBytes += byteCount
        emitByteCountsIfNeeded(at: 0, requestEventSink: requestEventSink)
    }

    func completeNext(requestEventSink: LocalHTTPProxyServer.RequestEventSink?) {
        guard !requestsWaitingForResponse.isEmpty else { return }
        let entry = requestsWaitingForResponse.removeFirst()

        emitByteCounts(
            id: entry.id,
            byteCounts: entry.byteCounts,
            requestEventSink: requestEventSink
        )

        emit(
            .statusChanged(
                id: entry.id,
                status: .succeeded
            ),
            requestEventSink: requestEventSink
        )
    }

    func failAll(requestEventSink: LocalHTTPProxyServer.RequestEventSink?) {
        for entry in requestsWaitingForResponse {
            emitByteCounts(
                id: entry.id,
                byteCounts: entry.byteCounts,
                requestEventSink: requestEventSink
            )

            emit(
                .statusChanged(
                    id: entry.id,
                    status: .failed
                ),
                requestEventSink: requestEventSink
            )
        }

        requestsWaitingForResponse.removeAll(keepingCapacity: true)
    }

    private func emitByteCountsIfNeeded(
        at index: Int,
        requestEventSink: LocalHTTPProxyServer.RequestEventSink?
    ) {
        guard requestsWaitingForResponse.indices.contains(index) else { return }

        let entry = requestsWaitingForResponse[index]
        let requestDelta = entry.byteCounts.requestBytes - entry.lastEmittedByteCounts.requestBytes
        let responseDelta = entry.byteCounts.responseBytes - entry.lastEmittedByteCounts.responseBytes

        guard requestDelta >= Reporting.minimumDelta || responseDelta >= Reporting.minimumDelta else {
            return
        }

        emitByteCounts(at: index, requestEventSink: requestEventSink)
    }

    private func emitByteCounts(
        at index: Int,
        requestEventSink: LocalHTTPProxyServer.RequestEventSink?
    ) {
        guard requestsWaitingForResponse.indices.contains(index) else { return }

        requestsWaitingForResponse[index].lastEmittedByteCounts = requestsWaitingForResponse[index].byteCounts
        let entry = requestsWaitingForResponse[index]

        emitByteCounts(
            id: entry.id,
            byteCounts: entry.byteCounts,
            requestEventSink: requestEventSink
        )
    }

    private func emitByteCounts(
        id: CapturedNetworkRequest.ID,
        byteCounts: CapturedNetworkRequestByteCounts,
        requestEventSink: LocalHTTPProxyServer.RequestEventSink?
    ) {
        emit(
            .byteCountsChanged(id: id, byteCounts: byteCounts),
            requestEventSink: requestEventSink
        )
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

private extension HTTPRequestHead {
    var requestHeaderByteCount: Int {
        let requestLine = "\(method.rawValue) \(uri.isEmpty ? "/" : uri) HTTP/\(version.major).\(version.minor)\r\n"
        return requestLine.utf8.count + headers.httpHeaderBlockByteCount
    }
}

private extension HTTPResponseHead {
    var responseHeaderByteCount: Int {
        let statusLine = "HTTP/\(version.major).\(version.minor) \(status.code) \(status.reasonPhrase)\r\n"
        return statusLine.utf8.count + headers.httpHeaderBlockByteCount
    }
}

private extension HTTPHeaders {
    var httpHeaderByteCount: Int {
        guard !isEmpty else {
            return 0
        }

        return httpHeaderBlockByteCount
    }

    var httpHeaderBlockByteCount: Int {
        var byteCount = 2

        for (name, value) in self {
            byteCount += name.utf8.count
            byteCount += 2
            byteCount += value.utf8.count
            byteCount += 2
        }

        return byteCount
    }
}

private extension Optional where Wrapped == HTTPHeaders {
    var httpHeaderByteCount: Int {
        guard let self, !self.isEmpty else {
            return 0
        }

        return self.httpHeaderBlockByteCount
    }
}

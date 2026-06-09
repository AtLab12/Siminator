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
    private let processResolver: ProcessResolver

    init(requestEventSink: RequestEventSink? = nil) {
        self.requestEventSink = requestEventSink
        self.processResolver = .init()
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
                channel.pipeline.addHandlers([
                    HTTPProxyForwardingHandler(requestEventSink: requestEventSink),
                    AttributionHandler(resolver: self.processResolver)
                ])
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

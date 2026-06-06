import Foundation
import NIOCore
import NIOPosix

actor LocalHTTPProxyServer {
    private let host = "127.0.0.1"
    private var channel: Channel?
    private var eventLoopGroup: MultiThreadedEventLoopGroup?

    var isRunning: Bool {
        channel != nil
    }

    func start(port: Int = 9090) async throws -> Int {
        if channel != nil {
            return port
        }

        let group = MultiThreadedEventLoopGroup(numberOfThreads: System.coreCount)
        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.backlog, value: 256)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelInitializer { channel in
                channel.pipeline.addHandler(ProxyConnectionLoggingHandler())
            }
            .childChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            .childChannelOption(ChannelOptions.maxMessagesPerRead, value: 16)
            .childChannelOption(ChannelOptions.recvAllocator, value: AdaptiveRecvByteBufferAllocator())

        do {
            let channel = try await bootstrap.bind(host: host, port: port).get()
            self.channel = channel
            eventLoopGroup = group
            print("Siminator proxy listening on \(channel.localAddress?.description ?? "\(host):\(port)")")
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

nonisolated final class ProxyConnectionLoggingHandler: ChannelInboundHandler, Sendable {
    typealias InboundIn = ByteBuffer

    func channelActive(context: ChannelHandlerContext) {
        print("Siminator proxy accepted connection from \(context.remoteAddress?.description ?? "unknown remote")")
        context.fireChannelActive()
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        let buffer = unwrapInboundIn(data)
        print("Siminator proxy received \(buffer.readableBytes) raw bytes")
        context.close(promise: nil)
    }

    func errorCaught(context: ChannelHandlerContext, error: Swift.Error) {
        print("Siminator proxy connection error: \(error)")
        context.close(promise: nil)
    }
}

import NIOCore
import NIOPosix

nonisolated struct SocketTuple: Hashable, Sendable {
    let localIP: String
    let localPort: UInt16
    let remoteIP: String
    let remotePort: UInt16
}

nonisolated final class AttributionHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = ByteBuffer

    private let resolver: ProcessResolver
//    private let iconStore: IconStore

    init(resolver: ProcessResolver) {
        self.resolver = resolver
    }

    func channelActive(context: ChannelHandlerContext) {
        guard
            let local = context.channel.localAddress,
            let remote = context.channel.remoteAddress,
            let tuple = SocketTuple.make(local: local, remote: remote)
        else {
            context.fireChannelActive()
            return
        }

        Task {
            if let app = try? await resolver.resolve(tuple: tuple) {
                print("resolved app to \(app.bundleID ?? "unknown bundle")")
//                await iconStore.remember(app: app, tuple: tuple)
            }
        }

        context.fireChannelActive()
    }
}

extension SocketTuple {
    nonisolated static func make(local: SocketAddress, remote: SocketAddress) -> SocketTuple? {
        guard
            let localIP = local.ipAddress,
            let localPort = local.port.map(UInt16.init),
            let remoteIP = remote.ipAddress,
            let remotePort = remote.port.map(UInt16.init)
        else {
            return nil
        }

        switch (local, remote) {
        case (.v4, .v4), (.v6, .v6):
            return .init(
                localIP: localIP,
                localPort: localPort,
                remoteIP: remoteIP,
                remotePort: remotePort
            )
        default:
            return nil
        }
    }
}

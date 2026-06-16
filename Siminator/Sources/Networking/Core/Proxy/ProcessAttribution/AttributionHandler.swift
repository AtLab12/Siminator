import Foundation
import NIOCore
import NIOPosix

nonisolated struct SocketTuple: Hashable, Sendable {
    let localPort: UInt16
    let remotePort: UInt16
}

/// Fired through the channel pipeline once the owning process of a
/// connection has been resolved, so the forwarding handler can attach
/// it to the captured request.
nonisolated struct ResolvedProcessEvent: Sendable {
    let process: CapturedRequestProcess
}

final nonisolated class AttributionHandler: ChannelInboundHandler, @unchecked Sendable {
    typealias InboundIn = ByteBuffer

    private let resolver: ProcessResolver
    private let iconStore: AppIconStore

    init(resolver: ProcessResolver, iconStore: AppIconStore) {
        self.resolver = resolver
        self.iconStore = iconStore
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

        let channel = context.channel
        let resolver = resolver
        let iconStore = iconStore

        Task {
            guard let app = try? await resolver.resolve(tuple: tuple) else {
                return
            }

            let process = CapturedRequestProcess(
                displayName: Self.displayName(for: app),
                bundleIdentifier: app.bundleID,
                executablePath: app.path.isEmpty ? nil : app.path
            )

            // Pipeline operations are thread-safe; this hops to the event
            // loop and reaches HTTPProxyForwardingHandler from the head.
            channel.pipeline.fireUserInboundEventTriggered(ResolvedProcessEvent(process: process))

            if app.bundleID != nil {
                await iconStore.ensureIcon(for: app)
            }
        }

        context.fireChannelActive()
    }

    private static func displayName(for app: ResolvedApp) -> String {
        if let name = app.runningApp?.localizedName, !name.isEmpty {
            return name
        }

        if !app.path.isEmpty {
            let executable = URL(fileURLWithPath: app.path).lastPathComponent
            if !executable.isEmpty {
                return executable
            }
        }

        return app.bundleID ?? CapturedRequestProcess.unknown.displayName
    }
}

extension SocketTuple {
    nonisolated static func make(local: SocketAddress, remote: SocketAddress) -> SocketTuple? {
        guard
            let localPort = local.port.map(UInt16.init),
            let remotePort = remote.port.map(UInt16.init)
        else {
            return nil
        }

        switch (local, remote) {
        case (.v4, .v4), (.v6, .v6):
            return .init(
                localPort: localPort,
                remotePort: remotePort
            )
        default:
            return nil
        }
    }
}

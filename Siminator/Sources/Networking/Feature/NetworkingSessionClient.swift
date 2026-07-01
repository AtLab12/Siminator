import ComposableArchitecture
import Foundation

struct NetworkingSessionClient: Sendable {
    struct StartResult: Sendable {
        var port: Int
        var routedServices: [String]
    }

    var requestEvents: @Sendable () async -> AsyncStream<CapturedNetworkRequestEvent>
    var startCapture: @Sendable () async throws -> StartResult
    var stopCapture: @Sendable () async throws -> Void
}

extension NetworkingSessionClient: DependencyKey {
    static let liveValue: Self = {
        let broadcaster = CapturedRequestEventBroadcaster()
        let certificateMaterialManager = CertificateMaterialManager()
        let proxyServer = LocalHTTPProxyServer(
            appIconStore: AppIconStore(cache: .shared),
            certificateMaterialManager: certificateMaterialManager,
            requestEventSink: { event in
                Task {
                    await broadcaster.yield(event)
                }
            }
        )
        let systemProxySettingsManager = SystemProxySettingsManager()

        return Self(
            requestEvents: {
                await broadcaster.events()
            },
            startCapture: {
                let port = try await proxyServer.start(port: ProxyConstants.port)

                do {
                    let services = try await systemProxySettingsManager.enableProxy(
                        host: ProxyConstants.host,
                        port: port
                    )
                    return StartResult(port: port, routedServices: services)
                } catch {
                    try? await proxyServer.stop()
                    throw error
                }
            },
            stopCapture: {
                var caughtError: (any Error)?

                do {
                    try await systemProxySettingsManager.restoreProxySettings()
                } catch {
                    caughtError = error
                }

                do {
                    try await proxyServer.stop()
                } catch {
                    caughtError = caughtError ?? error
                }

                if let caughtError {
                    throw caughtError
                }
            }
        )
    }()
}

extension DependencyValues {
    var networkingSessionClient: NetworkingSessionClient {
        get { self[NetworkingSessionClient.self] }
        set { self[NetworkingSessionClient.self] = newValue }
    }
}

private actor CapturedRequestEventBroadcaster {
    private var continuations: [UUID: AsyncStream<CapturedNetworkRequestEvent>.Continuation] = [:]

    func events() -> AsyncStream<CapturedNetworkRequestEvent> {
        AsyncStream { continuation in
            let id = UUID()
            insert(continuation, id: id)

            continuation.onTermination = { @Sendable _ in
                Task {
                    await self.remove(id: id)
                }
            }
        }
    }

    func yield(_ event: CapturedNetworkRequestEvent) {
        for continuation in continuations.values {
            continuation.yield(event)
        }
    }

    private func insert(
        _ continuation: AsyncStream<CapturedNetworkRequestEvent>.Continuation,
        id: UUID
    ) {
        continuations[id] = continuation
    }

    private func remove(id: UUID) {
        continuations[id] = nil
    }
}

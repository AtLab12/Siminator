import Foundation

actor SystemProxySettingsManager {
    private let helperClient = PrivilegedProxyHelperClient()

    // Enables the proxy for the given host and port on all enabled network services
    func enableProxy(host: String, port: Int) async throws -> [String] {
        try await helperClient.enableProxy(host: host, port: port)
    }

    func restoreProxySettings() async throws {
        try await helperClient.restoreProxySettings()
    }
}

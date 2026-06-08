import Foundation

enum ProxyHelperConstants {
    nonisolated static let machServiceName = "dev.atlab.Siminator.ProxyHelper"
    nonisolated static let executableName = "SiminatorProxyHelper"
    nonisolated static let launchDaemonPlistName = "\(machServiceName).plist"
}

@objc(SiminatorProxyHelperProtocol)
protocol ProxyHelperProtocol {
    nonisolated func enableProxy(
        host: String,
        port: NSNumber,
        withReply reply: @escaping (NSArray?, NSString?) -> Void
    )

    nonisolated func restoreProxySettings(withReply reply: @escaping (NSString?) -> Void)
}

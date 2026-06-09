import Foundation
import NIOCore
import NIOPosix

nonisolated struct HTTPProxyDestination: Sendable {
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

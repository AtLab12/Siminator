import Foundation

nonisolated final class PrivilegedProxyHelperClient: Sendable {
    private let installer = PrivilegedProxyHelperInstaller()

    func enableProxy(host: String, port: Int) async throws -> [String] {
        try installer.installIfNeeded()

        let connection = makeConnection()
        defer { connection.invalidate() }

        return try await withCheckedThrowingContinuation { continuation in
            guard let service = connection.remoteObjectProxyWithErrorHandler({ error in
                continuation.resume(throwing: error)
            }) as? ProxyHelperProtocol else {
                continuation.resume(throwing: PrivilegedProxyHelperError.connectionFailed)
                return
            }

            service.enableProxy(host: host, port: NSNumber(value: port)) { services, errorMessage in
                if let errorMessage {
                    continuation.resume(throwing: PrivilegedProxyHelperError.helperFailed(String(errorMessage)))
                } else {
                    continuation.resume(returning: (services as? [String]) ?? [])
                }
            }
        }
    }

    func restoreProxySettings() async throws {
        try installer.installIfNeeded()

        let connection = makeConnection()
        defer { connection.invalidate() }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            guard let service = connection.remoteObjectProxyWithErrorHandler({ error in
                continuation.resume(throwing: error)
            }) as? ProxyHelperProtocol else {
                continuation.resume(throwing: PrivilegedProxyHelperError.connectionFailed)
                return
            }

            service.restoreProxySettings { errorMessage in
                if let errorMessage {
                    continuation.resume(throwing: PrivilegedProxyHelperError.helperFailed(String(errorMessage)))
                } else {
                    continuation.resume()
                }
            }
        }
    }

    private func makeConnection() -> NSXPCConnection {
        let connection = NSXPCConnection(
            machServiceName: ProxyHelperConstants.machServiceName,
            options: .privileged
        )
        connection.remoteObjectInterface = NSXPCInterface(with: ProxyHelperProtocol.self)
        connection.resume()
        return connection
    }
}

struct PrivilegedProxyHelperInstaller: Sendable {
    private let helperDestinationURL = URL(
        fileURLWithPath: "/Library/PrivilegedHelperTools/\(ProxyHelperConstants.executableName)"
    )

    private let launchDaemonURL = URL(
        fileURLWithPath: "/Library/LaunchDaemons/\(ProxyHelperConstants.launchDaemonPlistName)"
    )

    nonisolated func installIfNeeded() throws {
        let isInstalled = FileManager.default.fileExists(atPath: helperDestinationURL.path)
            && FileManager.default.fileExists(atPath: launchDaemonURL.path)

        if isInstalled {
            // Reinstall when the bundled helper changed, so fixes ship to existing installs.
            guard let bundledHelperURL,
                  !FileManager.default.contentsEqual(atPath: bundledHelperURL.path, andPath: helperDestinationURL.path)
            else {
                return
            }
        }

        guard let bundledHelperURL else {
            throw PrivilegedProxyHelperError.bundledHelperMissing
        }

        let temporaryPlistURL = try writeTemporaryLaunchDaemonPlist()

        defer {
            try? FileManager.default.removeItem(at: temporaryPlistURL)
        }

        let command = [
            "mkdir -p /Library/PrivilegedHelperTools",
            "cp \(shellQuoted(bundledHelperURL.path)) \(shellQuoted(helperDestinationURL.path))",
            "chown root:wheel \(shellQuoted(helperDestinationURL.path))",
            "chmod 755 \(shellQuoted(helperDestinationURL.path))",
            "cp \(shellQuoted(temporaryPlistURL.path)) \(shellQuoted(launchDaemonURL.path))",
            "chown root:wheel \(shellQuoted(launchDaemonURL.path))",
            "chmod 644 \(shellQuoted(launchDaemonURL.path))",
            "launchctl bootout system/\(ProxyHelperConstants.machServiceName) >/dev/null 2>&1 || true",
            "launchctl bootstrap system \(shellQuoted(launchDaemonURL.path))",
            "launchctl kickstart -k system/\(ProxyHelperConstants.machServiceName)"
        ].joined(separator: " && ")

        try runPrivilegedShell(command)
    }

    nonisolated private var bundledHelperURL: URL? {
        let appBundleHelperURL = Bundle.main.bundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("PrivilegedHelperTools", isDirectory: true)
            .appendingPathComponent(ProxyHelperConstants.executableName)

        if FileManager.default.fileExists(atPath: appBundleHelperURL.path) {
            return appBundleHelperURL
        }

        let debugBuildHelperURL = Bundle.main.bundleURL
            .deletingLastPathComponent()
            .appendingPathComponent(ProxyHelperConstants.executableName)

        if FileManager.default.fileExists(atPath: debugBuildHelperURL.path) {
            return debugBuildHelperURL
        }

        return nil
    }

    nonisolated private func writeTemporaryLaunchDaemonPlist() throws -> URL {
        let plistURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(ProxyHelperConstants.launchDaemonPlistName)

        try launchDaemonPlist.write(to: plistURL, atomically: true, encoding: .utf8)
        return plistURL
    }

    nonisolated private var launchDaemonPlist: String {
        """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(ProxyHelperConstants.machServiceName)</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(helperDestinationURL.path)</string>
            </array>
            <key>MachServices</key>
            <dict>
                <key>\(ProxyHelperConstants.machServiceName)</key>
                <true/>
            </dict>
            <key>RunAtLoad</key>
            <true/>
        </dict>
        </plist>
        """
    }

    nonisolated private func runPrivilegedShell(_ command: String) throws {
        let appleScript = """
        do shell script \(appleScriptQuoted(command)) with administrator privileges
        """

        _ = try ExecutableHelper().runExecutable(
            "/usr/bin/osascript",
            arguments: ["-e", appleScript]
        )
    }

    nonisolated private func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    nonisolated private func appleScriptQuoted(_ value: String) -> String {
        let escapedBackslashes = value.replacingOccurrences(of: "\\", with: "\\\\")
        let escapedQuotes = escapedBackslashes.replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escapedQuotes)\""
    }
}

enum PrivilegedProxyHelperError: LocalizedError {
    case bundledHelperMissing
    case connectionFailed
    case helperFailed(String)

    var errorDescription: String? {
        switch self {
        case .bundledHelperMissing:
            "Could not find the bundled proxy helper executable."
        case .connectionFailed:
            "Could not connect to the proxy helper."
        case let .helperFailed(message):
            message
        }
    }
}

import Foundation

actor SystemProxySettingsManager {
    private struct ServiceProxyState {
        let service: String
        let webProxy: ProxyState
        let secureWebProxy: ProxyState
    }

    private struct ProxyState {
        let isEnabled: Bool
        let server: String
        let port: String
    }

    private var previousStates: [ServiceProxyState] = []

    // Enables the proxy for the given host and port on all enabled network services
    func enableProxy(host: String, port: Int) throws -> [String] {
        let services = try enabledNetworkServices()
        guard !services.isEmpty else {
            throw ProxyError.noNetworkServices
        }

        previousStates = try services.map { service in
            ServiceProxyState(
                service: service,
                webProxy: try readProxyState(service: service, kind: .web),
                secureWebProxy: try readProxyState(service: service, kind: .secureWeb)
            )
        }

        let commands = services.flatMap { service in
            [
                networkSetupCommand(["-setwebproxy", service, host, "\(port)", "off"]),
                networkSetupCommand(["-setsecurewebproxy", service, host, "\(port)", "off"]),
                networkSetupCommand(["-setwebproxystate", service, "on"]),
                networkSetupCommand(["-setsecurewebproxystate", service, "on"])
            ]
        }

        try runPrivilegedShell(commands.joined(separator: " && "))
        return services
    }

    func restoreProxySettings() throws {
        guard !previousStates.isEmpty else { return }

        let commands = previousStates.flatMap { state in
            restoreCommands(for: state.service, option: .web, state: state.webProxy)
            + restoreCommands(for: state.service, option: .secureWeb, state: state.secureWebProxy)
        }

        try runPrivilegedShell(commands.joined(separator: " && "))
        previousStates = []
    }

    // Returns a list of all network services that are currently enabled
    private func enabledNetworkServices() throws -> [String] {
        let output = try ExecutableHelper().runExecutable(
            "/usr/sbin/networksetup",
            arguments: ["-listallnetworkservices"]
        )

        return output
            .split(separator: "\n")
            .map(String.init)
            .filter { line in
                !line.hasPrefix("An asterisk")
                    && !line.hasPrefix("*")
                    && !line.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
    }

    private func readProxyState(service: String, kind: ProxyKind) throws -> ProxyState {
        let output = try ExecutableHelper().runExecutable(
            "/usr/sbin/networksetup",
            arguments: [kind.readCommand, service]
        )

        return ProxyState(
            isEnabled: value(for: "Enabled", in: output) == "Yes",
            server: value(for: "Server", in: output) ?? "",
            port: value(for: "Port", in: output) ?? "0"
        )
    }

    // Returns a list of commands to restore the proxy settings for the given service
    private func restoreCommands(
        for service: String,
        option: ProxyKind,
        state: ProxyState
    ) -> [String] {
        var commands: [String] = []

        if !state.server.isEmpty, state.port != "0" {
            commands.append(networkSetupCommand([option.writeCommand, service, state.server, state.port, "off"]))
        }

        commands.append(networkSetupCommand([option.stateCommand, service, state.isEnabled ? "on" : "off"]))
        return commands
    }

    // Helper func for extracting data
    private func value(for key: String, in output: String) -> String? {
        output
            .split(separator: "\n")
            .map(String.init)
            .first { $0.hasPrefix("\(key):") }?
            .dropFirst(key.count + 1)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func networkSetupCommand(_ arguments: [String]) -> String {
        ([ "/usr/sbin/networksetup" ] + arguments)
            .map(shellQuoted)
            .joined(separator: " ")
    }

    private func shellQuoted(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    // TODO: - Left as an mvp for now. To be refactored and automated
    private func runPrivilegedShell(_ command: String) throws {
        let appleScript = """
        do shell script \(appleScriptQuoted(command)) with administrator privileges
        """

        _ = try ExecutableHelper().runExecutable(
            "/usr/bin/osascript",
            arguments: ["-e", appleScript]
        )
    }

    private func appleScriptQuoted(_ value: String) -> String {
        let escapedBackslashes = value.replacingOccurrences(of: "\\", with: "\\\\")
        let escapedQuotes = escapedBackslashes.replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escapedQuotes)\""
    }

    
}

private enum ProxyKind {
    case web
    case secureWeb

    nonisolated var readCommand: String {
        switch self {
        case .web: "-getwebproxy"
        case .secureWeb: "-getsecurewebproxy"
        }
    }

    nonisolated var writeCommand: String {
        switch self {
        case .web: "-setwebproxy"
        case .secureWeb: "-setsecurewebproxy"
        }
    }

    nonisolated var stateCommand: String {
        switch self {
        case .web: "-setwebproxystate"
        case .secureWeb: "-setsecurewebproxystate"
        }
    }
}

private enum ProxyError: Error {
    case noNetworkServices
}

import Foundation

nonisolated final class ProxyHelperService: NSObject, NSXPCListenerDelegate, ProxyHelperProtocol {
    private let configurator = ProxyConfigurator()

    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection connection: NSXPCConnection
    ) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: ProxyHelperProtocol.self)
        connection.exportedObject = self
        connection.resume()
        return true
    }

    func enableProxy(
        host: String,
        port: NSNumber,
        withReply reply: @escaping (NSArray?, NSString?) -> Void
    ) {
        do {
            let services = try configurator.enableProxy(host: host, port: port.intValue)
            reply(services as NSArray, nil)
        } catch {
            reply(nil, error.localizedDescription as NSString)
        }
    }

    func restoreProxySettings(withReply reply: @escaping (NSString?) -> Void) {
        do {
            try configurator.restoreProxySettings()
            reply(nil)
        } catch {
            reply(error.localizedDescription as NSString)
        }
    }
}

nonisolated final class ProxyConfigurator {
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

    func enableProxy(host: String, port: Int) throws -> [String] {
        let services = try enabledNetworkServices()
        guard !services.isEmpty else {
            throw ProxyHelperError.noNetworkServices
        }

        // Keep the oldest snapshot if enable is called twice without a restore in between.
        if previousStates.isEmpty {
            previousStates = try services.map { service in
                ServiceProxyState(
                    service: service,
                    webProxy: sanitizedPreviousState(
                        try readProxyState(service: service, kind: .web),
                        host: host,
                        port: port
                    ),
                    secureWebProxy: sanitizedPreviousState(
                        try readProxyState(service: service, kind: .secureWeb),
                        host: host,
                        port: port
                    )
                )
            }
        }

        for service in services {
            _ = try runNetworkSetup(["-setwebproxy", service, host, "\(port)", "off"])
            _ = try runNetworkSetup(["-setsecurewebproxy", service, host, "\(port)", "off"])
            _ = try runNetworkSetup(["-setwebproxystate", service, "on"])
            _ = try runNetworkSetup(["-setsecurewebproxystate", service, "on"])
        }

        return services
    }

    func restoreProxySettings() throws {
        // Force the proxy off everywhere instead of silently succeeding.
        guard !previousStates.isEmpty else {
            try disableProxyOnAllServices()
            return
        }

        var firstError: Error?

        for state in previousStates {
            do {
                try restoreProxy(service: state.service, option: .web, state: state.webProxy)
                try restoreProxy(service: state.service, option: .secureWeb, state: state.secureWebProxy)
            } catch {
                firstError = firstError ?? error
            }
        }

        previousStates = []

        if let firstError {
            throw firstError
        }
    }

    private func disableProxyOnAllServices() throws {
        let services = try enabledNetworkServices()
        var firstError: Error?

        for service in services {
            do {
                _ = try runNetworkSetup([ProxyKind.web.stateCommand, service, "off"])
                _ = try runNetworkSetup([ProxyKind.secureWeb.stateCommand, service, "off"])
            } catch {
                firstError = firstError ?? error
            }
        }

        if let firstError {
            throw firstError
        }
    }

    private func sanitizedPreviousState(_ state: ProxyState, host: String, port: Int) -> ProxyState {
        // A stale Siminator proxy left over from a crashed session must never be treated as the user's original configuration.
        guard state.server == host, state.port == "\(port)" else {
            return state
        }

        return ProxyState(isEnabled: false, server: "", port: "0")
    }

    private func enabledNetworkServices() throws -> [String] {
        let output = try runNetworkSetup(["-listallnetworkservices"])

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
        let output = try runNetworkSetup([kind.readCommand, service])

        return ProxyState(
            isEnabled: value(for: "Enabled", in: output) == "Yes",
            server: value(for: "Server", in: output) ?? "",
            port: value(for: "Port", in: output) ?? "0"
        )
    }

    private func restoreProxy(
        service: String,
        option: ProxyKind,
        state: ProxyState
    ) throws {
        if !state.server.isEmpty, state.port != "0" {
            _ = try runNetworkSetup([option.writeCommand, service, state.server, state.port, "off"])
        }

        _ = try runNetworkSetup([option.stateCommand, service, state.isEnabled ? "on" : "off"])
    }

    private func value(for key: String, in output: String) -> String? {
        output
            .split(separator: "\n")
            .map(String.init)
            .first { $0.hasPrefix("\(key):") }?
            .dropFirst(key.count + 1)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func runNetworkSetup(_ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        process.arguments = arguments

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        try process.run()
        process.waitUntilExit()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            throw ProxyHelperError.commandFailed(
                executable: "networksetup",
                output: output.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        return output
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

private enum ProxyHelperError: LocalizedError {
    case noNetworkServices
    case commandFailed(executable: String, output: String)

    var errorDescription: String? {
        switch self {
        case .noNetworkServices:
            "No enabled network services were found."
        case let .commandFailed(executable, output):
            if output.isEmpty {
                "\(executable) failed without output."
            } else {
                "\(executable) failed: \(output)"
            }
        }
    }
}

let service = ProxyHelperService()
let listener = NSXPCListener(machServiceName: ProxyHelperConstants.machServiceName)
listener.delegate = service
listener.resume()
RunLoop.main.run()

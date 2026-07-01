import Foundation

enum CapturedRequestStatus: Sendable {
    case inProgress
    case succeeded
    case failed
}

struct CapturedRequestProcess: Hashable, Sendable {
    var displayName: String
    var bundleIdentifier: String?
    var executablePath: String?

    nonisolated static let unknown = CapturedRequestProcess(
        displayName: "Background Process",
        bundleIdentifier: nil,
        executablePath: nil
    )
}

struct CapturedNetworkRequest: Identifiable, Sendable {
    let id: UUID
    var startedAt: Date = .init()
    var completedAt: Date?
    var method: String
    var scheme: String
    var host: String
    var port: Int
    var path: String
    var status: CapturedRequestStatus
    var process: CapturedRequestProcess

    var displayURL: String {
        if method.uppercased() == "CONNECT" {
            return port == 443 ? "https://\(host)" : "https://\(host):\(port)"
        }

        if path.hasPrefix("http://") || path.hasPrefix("https://") {
            return path
        }

        let portSuffix = shouldDisplayPort ? ":\(port)" : ""
        return "\(scheme)://\(host)\(portSuffix)\(path.hasPrefix("/") ? "" : "/")\(path)"
    }

    private var shouldDisplayPort: Bool {
        switch (scheme.lowercased(), port) {
        case ("http", 80), ("https", 443):
            return false
        default:
            return true
        }
    }
}

enum CapturedNetworkRequestEvent: Sendable {
    case started(CapturedNetworkRequest)
    case statusChanged(id: CapturedNetworkRequest.ID, status: CapturedRequestStatus)
    case processResolved(id: CapturedNetworkRequest.ID, process: CapturedRequestProcess)
}

struct NetworkingCaptureSession {
    var title: String

    init(date: Date = Date()) {
        title = NetworkingCaptureSession.defaultTitle(for: date)
    }

    private nonisolated static func defaultTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "d-M-y-HH:mm:ss"
        return "\(formatter.string(from: date))-Simsession"
    }
}

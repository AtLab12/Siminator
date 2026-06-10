import Foundation

enum CapturedRequestStatus: String, Codable, CaseIterable, Sendable {
    case inProgress
    case succeeded
    case failed
}

struct CapturedRequestProcess: Codable, Hashable, Sendable {
    var displayName: String
    var bundleIdentifier: String?
    var executablePath: String?

    nonisolated static let unknown = CapturedRequestProcess(
        displayName: "Background Process",
        bundleIdentifier: nil,
        executablePath: nil
    )
}

struct CapturedNetworkRequest: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let createdAt: Date
    var completedAt: Date?
    var method: String
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

        return "http://\(host)\(path.hasPrefix("/") ? "" : "/")\(path)"
    }
}

enum CapturedNetworkRequestEvent: Sendable {
    case started(CapturedNetworkRequest)
    case statusChanged(id: CapturedNetworkRequest.ID, status: CapturedRequestStatus, completedAt: Date?)
    case processResolved(id: CapturedNetworkRequest.ID, process: CapturedRequestProcess)
}

struct NetworkingCaptureSession: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    let createdAt: Date
    var title: String

    init(createdAt: Date = Date()) {
        id = UUID()
        self.createdAt = createdAt
        title = NetworkingCaptureSession.defaultTitle(for: createdAt)
    }

    nonisolated private static func defaultTitle(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "d-M-y-HH:mm:ss"
        return "\(formatter.string(from: date))-Siminatorsession"
    }
}

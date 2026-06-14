import Foundation

/// Closely works with NetworkingSidebarController
/// Exists as a bridge between underlying proxy logic and view state
@MainActor
@Observable
final class NetworkingSidebarVM {
    var isDetached = false
    var isCaptureStarting = false
    var isCaptureStopping = false
    var isCaptureRunning = false
    var captureStatus = "Proxy stopped"
    var proxyRoutingStatus = "System proxy disabled"
    var isCertificateGenerating = false
    var isCertificateGenerated = false
    var certificateStatus = "Certificate not generated"
    let sessionViewModel: SessionLogVM

    var clearSessionButtonVisible: Bool {
        !sessionViewModel.visibleRequests.isEmpty
    }

    init() {
        sessionViewModel = .init()
    }

    func handleRequestEvent(_ event: CapturedNetworkRequestEvent) {
        sessionViewModel.handleRequestEvent(event)
    }

    func clearSession() {
        sessionViewModel.clearSession()
    }

    func beginNewSession() {
        sessionViewModel.beginNewSession()
    }
}

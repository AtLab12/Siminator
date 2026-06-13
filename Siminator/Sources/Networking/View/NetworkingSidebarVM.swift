//
//  NetworkingSidebarVM.swift
//  Siminator
//
//  Created by Mikolaj Zawada on 08/06/2026.
//

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

    init(
        isDetached: Bool = false,
        isCaptureStarting: Bool = false,
        isCaptureStopping: Bool = false,
        isCaptureRunning: Bool = false,
        captureStatus: String = "Proxy stopped",
        proxyRoutingStatus: String = "System proxy disabled",
        isCertificateGenerating: Bool = false,
        isCertificateGenerated: Bool = false,
        certificateStatus: String = "Certificate not generated"
    ) {
        self.isDetached = isDetached
        self.isCaptureStarting = isCaptureStarting
        self.isCaptureStopping = isCaptureStopping
        self.isCaptureRunning = isCaptureRunning
        self.captureStatus = captureStatus
        self.proxyRoutingStatus = proxyRoutingStatus
        self.isCertificateGenerating = isCertificateGenerating
        self.isCertificateGenerated = isCertificateGenerated
        self.certificateStatus = certificateStatus
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

//
//  NetworkingSidebarState.swift
//  Siminator
//
//  Created by Mikolaj Zawada on 08/06/2026.
//

import Foundation

@MainActor
@Observable
final class NetworkingSidebarState {
    private enum RequestBuffer {
        static let visibleLimit = 1_000
        static let trimBatchSize = 500
    }

    var isDetached = false
    var isCaptureStarting = false
    var isCaptureStopping = false
    var isCaptureRunning = false
    var captureStatus = "Proxy stopped"
    var proxyRoutingStatus = "System proxy disabled"
    var isCertificateInstalling = false
    var isCertificateTrusted = false
    var certificateStatus = "Certificate not trusted"
    var activeSession = NetworkingCaptureSession()
    var visibleRequests: [CapturedNetworkRequest] = []
    var totalRequestCount = 0

    @ObservationIgnored private var requestIndexes: [CapturedNetworkRequest.ID: Int] = [:]

    func beginNewSession() {
        activeSession = NetworkingCaptureSession()
        visibleRequests.removeAll(keepingCapacity: true)
        requestIndexes.removeAll(keepingCapacity: true)
        totalRequestCount = 0
    }

    func handleRequestEvent(_ event: CapturedNetworkRequestEvent) {
        switch event {
        case let .started(request):
            append(request)

        case let .statusChanged(id, status, completedAt):
            guard let index = requestIndexes[id], visibleRequests.indices.contains(index) else {
                return
            }

            visibleRequests[index].status = status
            visibleRequests[index].completedAt = completedAt

        case let .processResolved(id, process):
            guard let index = requestIndexes[id], visibleRequests.indices.contains(index) else {
                return
            }

            visibleRequests[index].process = process
        }
    }

    private func append(_ request: CapturedNetworkRequest) {
        totalRequestCount += 1
        visibleRequests.append(request)
        requestIndexes[request.id] = visibleRequests.count - 1

        guard visibleRequests.count > RequestBuffer.visibleLimit + RequestBuffer.trimBatchSize else {
            return
        }

        visibleRequests.removeFirst(RequestBuffer.trimBatchSize)
        rebuildRequestIndexes()
    }

    private func rebuildRequestIndexes() {
        requestIndexes.removeAll(keepingCapacity: true)

        for (index, request) in visibleRequests.enumerated() {
            requestIndexes[request.id] = index
        }
    }
}

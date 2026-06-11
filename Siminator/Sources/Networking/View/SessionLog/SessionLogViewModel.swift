import Foundation

@MainActor
@Observable
final class SessionLogVM {
    private enum RequestBuffer {
        static let visibleLimit = 10_000
        static let trimBatchSize = 500
    }
    
    var activeSession = NetworkingCaptureSession()
    public private(set) var visibleRequests: [CapturedNetworkRequest] = []
    var totalRequestCount = 0
    var logginSettingsEnabled: Bool = false
    
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
    
    func clearSession() {
        visibleRequests.removeAll(keepingCapacity: true)
        requestIndexes.removeAll(keepingCapacity: true)
        totalRequestCount = 0
    }
}


#if DEBUG
extension SessionLogVM {
    convenience init(requests: [CapturedNetworkRequest]) {
        self.init()
        requests.forEach {
            self.append($0)
        }
    }
}
#endif

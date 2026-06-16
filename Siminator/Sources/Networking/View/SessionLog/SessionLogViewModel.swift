import Foundation

struct SessionLogAppFilter: Identifiable, Hashable, Sendable {
    let id: String
    let process: CapturedRequestProcess

    var displayName: String {
        process.displayName
    }

    init(process: CapturedRequestProcess) {
        id = process.sessionLogFilterID
        self.process = process
    }
}

@MainActor
@Observable
final class SessionLogVM {
    private enum RequestBuffer {
        static let visibleLimit = 1000
        static let trimBatchSize = 500
    }

    var activeSession = NetworkingCaptureSession()
    private(set) var visibleRequests: [CapturedNetworkRequest] = []
    private(set) var filteredRequests: [CapturedNetworkRequest] = []
    private(set) var appFilters: [SessionLogAppFilter] = []
    var totalRequestCount = 0
    var logginSettingsEnabled: Bool = false {
        didSet {
            refreshFilteredRequests()
        }
    }

    var urlFilterText = "" {
        didSet {
            guard oldValue != urlFilterText else { return }
            refreshFilteredRequests()
        }
    }

    var selectedAppFilter: SessionLogAppFilter? {
        didSet {
            guard oldValue != selectedAppFilter else { return }
            refreshFilteredRequests()
        }
    }

    @ObservationIgnored private var requestIndexes: [CapturedNetworkRequest.ID: Int] = [:]

    func beginNewSession() {
        activeSession = NetworkingCaptureSession()
        visibleRequests.removeAll(keepingCapacity: true)
        filteredRequests.removeAll(keepingCapacity: true)
        appFilters.removeAll(keepingCapacity: true)
        requestIndexes.removeAll(keepingCapacity: true)
        totalRequestCount = 0
        selectedAppFilter = nil
    }

    func handleRequestEvent(_ event: CapturedNetworkRequestEvent) {
        switch event {
        case let .started(request):
            append(request)

        case let .statusChanged(id, status):
            guard let index = requestIndexes[id], visibleRequests.indices.contains(index) else {
                return
            }

            visibleRequests[index].status = status
            refreshFilteredRequests()

        case let .processResolved(id, process):
            guard let index = requestIndexes[id], visibleRequests.indices.contains(index) else {
                return
            }

            visibleRequests[index].process = process
            refreshAppFilters()
            refreshFilteredRequests()
        }
    }

    private func append(_ request: CapturedNetworkRequest) {
        totalRequestCount += 1
        visibleRequests.append(request)
        requestIndexes[request.id] = visibleRequests.count - 1

        guard visibleRequests.count > RequestBuffer.visibleLimit + RequestBuffer.trimBatchSize else {
            refreshAppFilters()
            refreshFilteredRequests()
            return
        }

        visibleRequests.removeFirst(RequestBuffer.trimBatchSize)
        rebuildRequestIndexes()
        refreshAppFilters()
        refreshFilteredRequests()
    }

    private func rebuildRequestIndexes() {
        requestIndexes.removeAll(keepingCapacity: true)

        for (index, request) in visibleRequests.enumerated() {
            requestIndexes[request.id] = index
        }
    }

    func clearSession() {
        visibleRequests.removeAll(keepingCapacity: true)
        filteredRequests.removeAll(keepingCapacity: true)
        appFilters.removeAll(keepingCapacity: true)
        requestIndexes.removeAll(keepingCapacity: true)
        totalRequestCount = 0
        selectedAppFilter = nil
    }

    var hasActiveFilters: Bool {
        !urlFilterText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedAppFilter != nil
    }

    private func refreshAppFilters() {
        var filtersByID: [SessionLogAppFilter.ID: SessionLogAppFilter] = [:]

        for request in visibleRequests {
            let filter = SessionLogAppFilter(process: request.process)
            filtersByID[filter.id] = filter
        }

        appFilters = filtersByID.values.sorted {
            let nameOrder = $0.displayName.localizedStandardCompare($1.displayName)
            if nameOrder == .orderedSame {
                return $0.id < $1.id
            }
            return nameOrder == .orderedAscending
        }
    }

    private func refreshFilteredRequests() {
        guard logginSettingsEnabled else {
            filteredRequests = visibleRequests
            return
        }

        let query = urlFilterText.trimmingCharacters(in: .whitespacesAndNewlines)
        let appFilter = selectedAppFilter

        guard !query.isEmpty || appFilter != nil else {
            filteredRequests = visibleRequests
            return
        }

        filteredRequests = visibleRequests.filter { request in
            let matchesURL = query.isEmpty || request.displayURL.range(
                of: query,
                options: [.caseInsensitive, .diacriticInsensitive]
            ) != nil
            let matchesApp = appFilter.map { request.process.sessionLogFilterID == $0.id } ?? true

            return matchesURL && matchesApp
        }
    }
}

private extension CapturedRequestProcess {
    var sessionLogFilterID: String {
        if let bundleIdentifier, !bundleIdentifier.isEmpty {
            return "bundle:\(bundleIdentifier)"
        }

        if let executablePath, !executablePath.isEmpty {
            return "path:\(executablePath)"
        }

        return "name:\(displayName)"
    }
}

#if DEBUG
    extension SessionLogVM {
        convenience init(requests: [CapturedNetworkRequest]) {
            self.init()
            for request in requests {
                append(request)
            }
        }
    }
#endif

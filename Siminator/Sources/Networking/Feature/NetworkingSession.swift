import ComposableArchitecture
import Foundation

@Reducer
struct NetworkingSession {
    private enum CancelID {
        case capture
        case requestEvents
    }

    @ObservableState
    struct State {
        private enum RequestBuffer {
            static let trimBatchSize = 500
            static let visibleLimit = 1000
        }

        var activeSession = NetworkingCaptureSession()
        var activeSessionTitle: String
        var appFilters: [SessionLogAppFilter] = []
        var captureStatus: CaptureStatus = .stopped
        var filteredRequests: [CapturedNetworkRequest] = []
        var selectedAppFilter: SessionLogAppFilter?
        var settingsEnabled = false
        var showAppFilter = false
        var showSessionBrowser = false
        var totalRequestCount = 0
        var urlFilterText = ""
        var visibleRequests: [CapturedNetworkRequest] = []

        @ObservationStateIgnored
        private var filteredRequestIndexes: [CapturedNetworkRequest.ID: Int] = [:]

        @ObservationStateIgnored
        private var requestIndexes: [CapturedNetworkRequest.ID: Int] = [:]

        init(
            activeSession: NetworkingCaptureSession = .init()
        ) {
            
            self.activeSession = activeSession
            activeSessionTitle = activeSession.title
        }

        var captureButtonSystemImage: String {
            captureStatus.isRunning ? "stop.fill" : "record.circle"
        }

        var captureButtonTitle: String {
            switch captureStatus {
            case .failed, .stopped:
                return "Start Capture"
            case .running:
                return "Stop Capture"
            case .starting:
                return "Starting ..."
            case .stopping:
                return "Stopping ..."
            }
        }

        var captureStatusText: String {
            switch captureStatus {
            case let .failed(message):
                return message
            case let .running(port, _):
                return "Listening on \(ProxyConstants.host):\(port)"
            case .starting:
                return "Starting proxy on \(ProxyConstants.host):\(ProxyConstants.port)"
            case .stopped:
                return "Proxy stopped"
            case .stopping:
                return "Stopping proxy"
            }
        }

        var hasActiveFilters: Bool {
            !urlFilterText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || selectedAppFilter != nil
        }

        var isCaptureTransitioning: Bool {
            captureStatus.isTransitioning
        }

        var isClearSessionVisible: Bool {
            !visibleRequests.isEmpty
        }

        var proxyRoutingStatus: String {
            switch captureStatus {
            case let .running(_, routedServices):
                if routedServices.isEmpty {
                    return "System proxy enabled"
                }
                return "Routing enabled: \(routedServices.joined(separator: ", "))"

            case .starting:
                return "Preparing system proxy"

            case .stopping:
                return "Restoring system proxy"

            case .failed, .stopped:
                return "System proxy disabled"
            }
        }

        var requestSummary: String? {
            if settingsEnabled, hasActiveFilters {
                return "Showing \(filteredRequests.count.formatted()) matching of \(visibleRequests.count.formatted()) recent requests"
            }

            if totalRequestCount > visibleRequests.count {
                return "Showing latest \(visibleRequests.count.formatted()) of \(totalRequestCount.formatted())"
            }

            return nil
        }
    }

    enum Action: BindableAction {
        case appFilterSelected(SessionLogAppFilter?)
        case binding(BindingAction<State>)
        case captureButtonTapped
        case clearSessionButtonTapped
        case clearURLFilterButtonTapped
        case requestEvent(CapturedNetworkRequestEvent)
        case requestEventsTask
        case sessionBrowserButtonTapped
        case settingsButtonTapped
        case startCaptureResponse(Result<NetworkingSessionClient.StartResult, any Error>)
        case stopCaptureResponse(Result<Void, any Error>)
    }

    @Dependency(\.date.now) var now
    @Dependency(\.networkingSessionClient) var networkingSessionClient

    var body: some ReducerOf<Self> {
        BindingReducer()

        Reduce { state, action in
            switch action {
            case let .appFilterSelected(appFilter):
                state.selectedAppFilter = appFilter
                state.showAppFilter = false
                state.refreshFilteredRequests()
                return .none

            case .binding(\.urlFilterText):
                state.refreshFilteredRequests()
                return .none

            case .binding:
                return .none

            case .captureButtonTapped:
                switch state.captureStatus {
                case .failed, .stopped:
                    state.beginNewSession(startedAt: now)
                    state.captureStatus = .starting
                    return .run { [networkingSessionClient] send in
                        await send(.startCaptureResponse(Result {
                            try await networkingSessionClient.startCapture()
                        }))
                    }
                    .cancellable(id: CancelID.capture, cancelInFlight: true)

                case .running:
                    state.captureStatus = .stopping
                    return .run { [networkingSessionClient] send in
                        await send(.stopCaptureResponse(Result {
                            try await networkingSessionClient.stopCapture()
                        }))
                    }
                    .cancellable(id: CancelID.capture, cancelInFlight: true)

                case .starting, .stopping:
                    return .none
                }

            case .clearSessionButtonTapped:
                state.clearSession()
                return .none

            case .clearURLFilterButtonTapped:
                state.urlFilterText = ""
                state.refreshFilteredRequests()
                return .none

            case let .requestEvent(event):
                state.handleRequestEvent(event)
                return .none

            case .requestEventsTask:
                return .run { [networkingSessionClient] send in
                    let events = await networkingSessionClient.requestEvents()
                    for await event in events {
                        await send(.requestEvent(event))
                    }
                }
                .cancellable(id: CancelID.requestEvents, cancelInFlight: true)

            case .sessionBrowserButtonTapped:
                state.showSessionBrowser.toggle()
                return .none

            case .settingsButtonTapped:
                state.settingsEnabled.toggle()
                state.refreshFilteredRequests()
                return .none

            case let .startCaptureResponse(.success(result)):
                state.captureStatus = .running(
                    port: result.port,
                    routedServices: result.routedServices
                )
                return .none

            case let .startCaptureResponse(.failure(error)):
                state.captureStatus = .failed(message: "Failed to start proxy: \(error.localizedDescription)")
                return .none

            case .stopCaptureResponse(.success):
                state.captureStatus = .stopped
                return .none

            case let .stopCaptureResponse(.failure(error)):
                state.captureStatus = .failed(message: "Failed to stop proxy: \(error.localizedDescription)")
                return .none
            }
        }
    }
}

extension NetworkingSession.State {
    enum CaptureStatus: Equatable {
        case failed(message: String)
        case running(port: Int, routedServices: [String])
        case starting
        case stopped
        case stopping

        var isRunning: Bool {
            if case .running = self {
                return true
            }
            return false
        }

        var isTransitioning: Bool {
            self == .starting || self == .stopping
        }
    }

    mutating func beginNewSession(startedAt date: Date) {
        activeSession = NetworkingCaptureSession(date: date)
        activeSessionTitle = activeSession.title
        clearSession()
    }

    mutating func clearSession() {
        appFilters.removeAll(keepingCapacity: true)
        filteredRequestIndexes.removeAll(keepingCapacity: true)
        filteredRequests.removeAll(keepingCapacity: true)
        requestIndexes.removeAll(keepingCapacity: true)
        selectedAppFilter = nil
        totalRequestCount = 0
        visibleRequests.removeAll(keepingCapacity: true)
    }

    mutating func handleRequestEvent(_ event: CapturedNetworkRequestEvent) {
        switch event {
        case let .started(request):
            append(request)

        case let .statusChanged(id, status):
            updateRequest(id: id) { request in
                request.status = status
            }

        case let .processResolved(id, process):
            updateRequest(id: id) { request in
                request.process = process
            }
            refreshAppFilters()
            refreshFilteredRequests()
        }
    }

    mutating func refreshFilteredRequests() {
        defer {
            rebuildFilteredRequestIndexes()
        }

        guard settingsEnabled else {
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

    private mutating func append(_ request: CapturedNetworkRequest) {
        totalRequestCount += 1
        visibleRequests.append(request)
        requestIndexes[request.id] = visibleRequests.count - 1

        if matchesActiveFilters(request) {
            filteredRequests.append(request)
            filteredRequestIndexes[request.id] = filteredRequests.count - 1
        }

        guard visibleRequests.count > RequestBuffer.visibleLimit + RequestBuffer.trimBatchSize else {
            refreshAppFilters()
            return
        }

        visibleRequests.removeFirst(RequestBuffer.trimBatchSize)
        rebuildRequestIndexes()
        refreshAppFilters()
        refreshFilteredRequests()
    }

    private func matchesActiveFilters(_ request: CapturedNetworkRequest) -> Bool {
        guard settingsEnabled else {
            return true
        }

        let query = urlFilterText.trimmingCharacters(in: .whitespacesAndNewlines)
        let matchesURL = query.isEmpty || request.displayURL.range(
            of: query,
            options: [.caseInsensitive, .diacriticInsensitive]
        ) != nil
        let matchesApp = selectedAppFilter.map { request.process.sessionLogFilterID == $0.id } ?? true

        return matchesURL && matchesApp
    }

    private mutating func rebuildFilteredRequestIndexes() {
        filteredRequestIndexes.removeAll(keepingCapacity: true)

        for (index, request) in filteredRequests.enumerated() {
            filteredRequestIndexes[request.id] = index
        }
    }

    private mutating func rebuildRequestIndexes() {
        requestIndexes.removeAll(keepingCapacity: true)

        for (index, request) in visibleRequests.enumerated() {
            requestIndexes[request.id] = index
        }
    }

    private mutating func refreshAppFilters() {
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

        if let selectedAppFilter, filtersByID[selectedAppFilter.id] == nil {
            self.selectedAppFilter = nil
        }
    }

    private mutating func updateRequest(
        id: CapturedNetworkRequest.ID,
        update: (inout CapturedNetworkRequest) -> Void
    ) {
        guard let index = requestIndexes[id], visibleRequests.indices.contains(index) else {
            return
        }

        update(&visibleRequests[index])

        if let filteredIndex = filteredRequestIndexes[id],
           filteredRequests.indices.contains(filteredIndex) {
            filteredRequests[filteredIndex] = visibleRequests[index]
        }
    }
}

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

extension CapturedRequestProcess {
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

import Foundation
import ComposableArchitecture

@Reducer
struct NetworkingFeature {
    
    @ObservableState
    struct State {

        var isDetached: Bool = false
        var rootCertificateStatus: CertificateStatus = .loading
        var isInstallingCertToSim = false
        var captureStatus: CaptureStatus = .stop
        var isClearSessionVisible: Bool = false
        
        var isTransitioning: Bool {
            captureStatus == .starting || captureStatus == .stopping
        }
        
        var captureButtonTitle: String {
            switch captureStatus {
            case .stop:
                return "Stopped"
            case .running:
                return "Running"
            case .starting:
                return "Starting ..."
            case .stopping:
                return "Stopping ..."
            }
        }
        
        @ObservationStateIgnored
        var sidebarController: NetworkingSidebarController?
        
        @ObservationStateIgnored
        let certificateMaterialManager = CertificateMaterialManager()
        
        enum CaptureStatus {
            case stop
            case running
            case starting
            case stopping
        }
    }
    
    enum Action {
        case domain(Domain)
        case connectController(NetworkingSidebarController)
        case networkingWindowToggled(Bool)
        case generateRootCertResult(CertificateMaterial?)
        case deleteAllResult(Bool)
        case deleteAllCertificatesPressed
        case checkIfCertificatesExist
        case loadCertificateResult(Bool)
        
        enum Domain {
            case onAppear
            case generateRootCertificatePressed
            case detachStatusToggled
            case installCertificateToSimPressed
        }
    }
    
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .domain(let domainAction):
                return handleDomainAction(&state, domainAction)
            case .connectController(let controller):
                state.sidebarController = controller
                return .none
            case .networkingWindowToggled(let value):
                return .run { [controller = state.sidebarController] send in
                    await MainActor.run {
                        controller?.setEnabled(value)
                    }
                }
            case .generateRootCertResult(let result):
                guard result != nil else {
                    state.rootCertificateStatus = .generationFailed
                    return .none
                }
                
                state.rootCertificateStatus = .generated
                return .none
            case .deleteAllCertificatesPressed:
                return .run { [certManager = state.certificateMaterialManager] send in
                    do {
                        try await certManager.deleteCertificateMaterial()
                        await send(.deleteAllResult(true))
                    } catch {
                        await send(.deleteAllResult(false))
                    }
                }
            case .deleteAllResult(let result):
                if result {
                    state.rootCertificateStatus = .requiresGenerating
                }
                return .none
            case .checkIfCertificatesExist:
                return .run { [certControll = state.certificateMaterialManager] send in
                    do {
                        let result = try await certControll.certificateState()
                        await send(.loadCertificateResult(result.isGenerated))
                    } catch {
                        await send(.loadCertificateResult(false))
                    }
                }
            case .loadCertificateResult(let value):
                if value {
                    state.rootCertificateStatus = .generated
                } else {
                    state.rootCertificateStatus = .requiresGenerating
                }
                return .none
            }
        }
    }
    
    private func handleDomainAction(_ state: inout NetworkingFeature.State, _ action: NetworkingFeature.Action.Domain) -> Effect<Action> {
        switch action {
        case .onAppear:
            return .send(.checkIfCertificatesExist)
        case .generateRootCertificatePressed:
            if state.rootCertificateStatus == .requiresGenerating {
                state.rootCertificateStatus = .generating
                return .run { [certManager = state.certificateMaterialManager] send in
                    let result = try await certManager.ensureCertificateMaterialExists()
                    await send(.generateRootCertResult(result))
                }
            }
            return .none
        case .detachStatusToggled:
            state.isDetached.toggle()
            return .run { [
                controller = state.sidebarController,
                isDetached = state.isDetached
            ] send in
                await controller?.setDetached(isDetached)
            }
        case .installCertificateToSimPressed:
            // TODO: - Implement this
            return .none
        }
    }
}

enum CertificateStatus: String {
    case generating = "Generation in progress"
    case generated = "Certificate generated"
    case installed = "Certificate installed"
    case requiresInstalling = "Please install the certificate"
    case requiresGenerating = "Please generate the certificate"
    case generationFailed = "Generation failed"
    case loading = "Loading ..."
}


/// Exists as a bridge between underlying proxy logic and view state
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
    var isInstallingOnSimulator = false
    var isSimulatorSelectionPopoverPresented = false
    var certificateStatus: CertificateStatus = .requiresGenerating
    let sessionViewModel: SessionLogVM

    var bootedDevices: [SimctlDevice] = []
    var processingSim: ProcessingSim?

    var installCertOnSimWithUDID: @MainActor (String) -> Void

    var clearSessionButtonVisible: Bool {
        !sessionViewModel.visibleRequests.isEmpty
    }

    init(installCertOnSimWithUDID: @MainActor @escaping (String) -> Void) {
        sessionViewModel = .init()
        self.installCertOnSimWithUDID = installCertOnSimWithUDID
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

    func simulatorSelectedWithId(_ udid: String) {
        processingSim = .init(udid: udid)
    }

    struct ProcessingSim {
        let udid: String
        var requiresReboot: Bool = false
    }
}

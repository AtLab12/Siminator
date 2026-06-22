import Foundation
import ComposableArchitecture

@Reducer
struct NetworkingFeature {
    
    @ObservableState
    struct State {
        var isDetached: Bool = false

        @ObservationStateIgnored
        var sidebarController: NetworkingSidebarController?
    }
    
    enum Action {
        case connectController(NetworkingSidebarController)
        case networkingWindowToggled(Bool)
    }
    
    
    var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .connectController(let controller):
                state.sidebarController = controller
                return .none
            case .networkingWindowToggled(let value):
                return .run { [controller = state.sidebarController] send in
                    await MainActor.run {
                        controller?.setEnabled(value)
                    }
                }
            }
        }
    }
}



/// Closely works with NetworkingSidebarController
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

    enum CertificateStatus: String {
        case generating = "Generation in progress"
        case generated = "Certificate generated"
        case installed = "Certificate installed"
        case requiresInstalling = "Please install the certificate"
        case requiresGenerating = "Please generate the certificate"
        case generationFailed = "Generation failed"
    }

    struct ProcessingSim {
        let udid: String
        var requiresReboot: Bool = false
    }
}

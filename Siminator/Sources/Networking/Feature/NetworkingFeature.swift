import AppKit
import ComposableArchitecture
import Foundation

@Reducer
struct NetworkingFeature {
    @ObservableState
    struct State {
        var isDetached: Bool
        var isInstallingCertToSim: Bool
        var isRebootingSimulators: Bool
        var rootCertificateStatus: CertificateStatus
        var session: NetworkingSession.State

        @ObservationStateIgnored
        var sidebarController: NetworkingSidebarController?

        @ObservationStateIgnored
        let certificateMaterialManager: CertificateMaterialManager

        init(
            isDetached: Bool = false,
            isInstallingCertToSim: Bool = false,
            isRebootingSimulators: Bool = false,
            rootCertificateStatus: CertificateStatus = .loading,
            sidebarController: NetworkingSidebarController? = nil,
            certificateMaterialManager: CertificateMaterialManager = .init(),
            session: NetworkingSession.State = .init()
        ) {
            self.isDetached = isDetached
            self.isInstallingCertToSim = isInstallingCertToSim
            self.isRebootingSimulators = isRebootingSimulators
            self.rootCertificateStatus = rootCertificateStatus
            self.sidebarController = sidebarController
            self.certificateMaterialManager = certificateMaterialManager
            self.session = session
        }
    }

    enum Action {
        case checkIfCertificatesExist
        case connectController(NetworkingSidebarController)
        case deleteAllCertificatesPressed
        case deleteAllResult(Bool)
        case generateRootCertResult(CertificateMaterial?)
        case installCertificateToSimResult(Result<Void, any Error>)
        case loadCertificateResult(Bool)
        case networkingWindowToggled(Bool)
        case rebootSimulatorsResult(Result<Void, any Error>)
        case session(NetworkingSession.Action)
        case view(View)

        enum View {
            case detachStatusToggled
            case generateRootCertificatePressed
            case installCertificateToSimPressed
            case onAppear
            case rebootSimulatorsPressed
        }
    }

    var body: some ReducerOf<Self> {
        Scope(state: \.session, action: \.session) {
            NetworkingSession()
        }

        Reduce { state, action in
            switch action {
            case .checkIfCertificatesExist:
                return .run { [certificateMaterialManager = state.certificateMaterialManager] send in
                    do {
                        let result = try await certificateMaterialManager.certificateState()
                        await send(.loadCertificateResult(result.isGenerated))
                    } catch {
                        await send(.loadCertificateResult(false))
                    }
                }

            case let .connectController(controller):
                state.sidebarController = controller
                return .none

            case .deleteAllCertificatesPressed:
                return .run { [certificateMaterialManager = state.certificateMaterialManager] send in
                    do {
                        try await certificateMaterialManager.deleteCertificateMaterial()
                        await send(.deleteAllResult(true))
                    } catch {
                        await send(.deleteAllResult(false))
                    }
                }

            case let .deleteAllResult(result):
                if result {
                    state.rootCertificateStatus = .requiresGenerating
                }
                return .none

            case let .generateRootCertResult(result):
                state.rootCertificateStatus = result == nil ? .generationFailed : .generated
                return .none

            case .installCertificateToSimResult(.success):
                state.isInstallingCertToSim = false
                state.rootCertificateStatus = .installed
                return .none

            case .installCertificateToSimResult(.failure):
                state.isInstallingCertToSim = false
                state.rootCertificateStatus = .installFailed
                return .none

            case let .loadCertificateResult(value):
                state.rootCertificateStatus = value ? .generated : .requiresGenerating
                return .none

            case let .networkingWindowToggled(value):
                return .run { [controller = state.sidebarController] _ in
                    await MainActor.run {
                        controller?.setEnabled(value)
                    }
                }

            case .rebootSimulatorsResult(.success):
                state.isRebootingSimulators = false
                state.rootCertificateStatus = .installed
                return .none

            case .rebootSimulatorsResult(.failure):
                state.isRebootingSimulators = false
                state.rootCertificateStatus = .rebootFailed
                return .none

            case .session:
                return .none

            case let .view(viewAction):
                return handleViewAction(viewAction, state: &state)
            }
        }
    }

    private func handleViewAction(
        _ action: Action.View,
        state: inout State
    ) -> Effect<Action> {
        switch action {
        case .detachStatusToggled:
            state.isDetached.toggle()
            return .run { [controller = state.sidebarController, isDetached = state.isDetached] _ in
                await controller?.setDetached(isDetached)
            }

        case .generateRootCertificatePressed:
            guard state.rootCertificateStatus == .requiresGenerating
                || state.rootCertificateStatus == .generationFailed else {
                return .none
            }

            state.rootCertificateStatus = .generating
            return .run { [certificateMaterialManager = state.certificateMaterialManager] send in
                do {
                    let result = try await certificateMaterialManager.ensureCertificateMaterialExists()
                    await send(.generateRootCertResult(result))
                } catch {
                    await send(.generateRootCertResult(nil))
                }
            }

        case .installCertificateToSimPressed:
            guard !state.isInstallingCertToSim else {
                return .none
            }

            state.isInstallingCertToSim = true
            return .run { [certificateMaterialManager = state.certificateMaterialManager] send in
                await send(
                    .installCertificateToSimResult(
                        Result {
                            try await certificateMaterialManager.installRootCertToBootedSimulator()
                        }
                    )
                )
            }

        case .onAppear:
            return .send(.checkIfCertificatesExist)

        case .rebootSimulatorsPressed:
            guard !state.isRebootingSimulators else {
                return .none
            }

            state.isRebootingSimulators = true
            return .run { [certificateMaterialManager = state.certificateMaterialManager] send in
                await send(
                    .rebootSimulatorsResult(
                        Result {
                            try await certificateMaterialManager.rebootBootedSimulators()
                        }
                    )
                )
            }
        }
    }
}

enum CertificateStatus: String {
    case generated = "Certificate generated"
    case generating = "Generation in progress"
    case generationFailed = "Generation failed"
    case installFailed = "Simulator certificate installation failed"
    case installed = "Certificate installed"
    case loading = "Loading ..."
    case rebootFailed = "Simulator reboot failed"
    case requiresGenerating = "Please generate the certificate"
    case requiresInstalling = "Please install the certificate"
}

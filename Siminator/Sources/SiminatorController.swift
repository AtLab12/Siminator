//
//  SiminatorController.swift
//  Siminator
//
//  Created by Mikolaj Zawada on 21/06/2026.
//

import Foundation
import AppKit
import ComposableArchitecture

@Reducer
struct SiminatorController {
    @ObservableState
    struct State {
        var tools: Tools.State
        var networking: NetworkingFeature.State
        
        @MainActor
        init() {
            self.tools = Tools.State()
            self.networking = NetworkingFeature.State()
        }
    }

    enum Action {
        case extraMenu(ExtraMenuAction)
        case networking(NetworkingFeature.Action)
        case tools(Tools.Action)
    }

    enum ExtraMenuAction {
        case quit
        case refreshCertificate
        case deleteCertificates
    }

    var body: some ReducerOf<Self> {
        
        Scope(\.networking, action: \.networking) {
            NetworkingFeature()
        }
        
        Scope(state: \.tools, action: \.tools) {
            Tools()
        }
        
        Reduce { state, action in
            switch action {
            case .extraMenu(let extraAction):
                return handleExtraAction(extraAction)
            
            // Networking
            case .networking:
                return .none
                
            // Tools
            case .tools(.delegate(.showNetworkingWindow(let value))):
                return .send(.networking(.networkingWindowToggled(value)))
                
            case .tools:
                return .none
            }
        }
    }

    private func handleExtraAction(_ action: ExtraMenuAction) -> Effect<Action> {
        switch action {
        case .quit:
            return .run { send in
                await MainActor.run {
                    NSApplication.shared.terminate(nil)
                }
            }
        case .refreshCertificate:
            return .none
        case .deleteCertificates:
            return .send(.networking(.deleteAllCertificatesPressed))
        }
    }
}

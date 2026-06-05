import Foundation
import SwiftUI

@MainActor
@Observable
final class ToolsHomeState {
    var showNetworkingSidebar = false
}

struct ToolsHomeView: View {
    @Bindable var state: ToolsHomeState

    let onNetworkingEnabledChanged: @MainActor (Bool) -> Void

    var body: some View {
        VStack {
            Text("Siminator by Mikolaj Zawada")
            
            Toggle(isOn: $state.showNetworkingSidebar) {
                Text("Show networking sidebar")
            }
            .toggleStyle(.switch)
            .onChange(of: state.showNetworkingSidebar) { _, isEnabled in
                onNetworkingEnabledChanged(isEnabled)
            }
        }
        .padding(16)
        .frame(width: 260, height: 180)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(.regularMaterial)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}

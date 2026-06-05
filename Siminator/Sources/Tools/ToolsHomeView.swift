import Foundation
import SwiftUI

final class ToolsHomeState: ObservableObject {
    @Published var showNetworkingSidebar = false
}

struct ToolsHomeView: View {
    @ObservedObject var state: ToolsHomeState

    let onNetworkingEnabledChanged: (Bool) -> Void

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

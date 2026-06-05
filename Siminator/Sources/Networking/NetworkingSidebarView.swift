import SwiftUI

@MainActor
@Observable
final class NetworkingSidebarState {
    var isDetached = false
}

struct NetworkingSidebarView: View {
    let state: NetworkingSidebarState

    let onDetachedChanged: @MainActor (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("Networking")
                    .font(.headline)

                Spacer()

                Button {
                    onDetachedChanged(!state.isDetached)
                } label: {
                    Image(systemName: state.isDetached ? "pin.fill" : "macwindow")
                }
                .buttonStyle(.borderless)
                .help(state.isDetached ? "Dock to simulator" : "Detach window")
            }

            Divider()

            Text("Requests will appear here")
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 18)
                .fill(.regularMaterial)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }
}

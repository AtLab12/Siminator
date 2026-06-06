import SwiftUI

@MainActor
@Observable
final class NetworkingSidebarState {
    var isDetached = false
    var isCaptureStarting = false
    var isCaptureRunning = false
    var proxyPort = 9090
    var captureStatus = "Proxy stopped"
    var proxyRoutingStatus = "System proxy disabled"
    var isCertificateInstalling = false
    var isCertificateTrusted = false
    var certificateStatus = "Certificate not trusted"
}

struct NetworkingSidebarView: View {
    let state: NetworkingSidebarState

    let onDetachedChanged: @MainActor (Bool) -> Void
    let onCaptureToggled: @MainActor () -> Void
    let onCertificateInstallRequested: @MainActor () -> Void

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

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Button {
                        onCertificateInstallRequested()
                    } label: {
                        Label(
                            state.isCertificateTrusted ? "Trusted" : "Trust Certificate",
                            systemImage: state.isCertificateTrusted ? "checkmark.shield.fill" : "shield"
                        )
                    }
                    .buttonStyle(.bordered)
                    .disabled(state.isCertificateInstalling)

                    if state.isCertificateInstalling {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                Text(state.certificateStatus)
                    .font(.caption)
                    .foregroundStyle(state.isCertificateTrusted ? .green : .secondary)
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Button {
                        onCaptureToggled()
                    } label: {
                        Label(
                            state.isCaptureRunning || state.isCaptureStarting ? "Stop" : "Start",
                            systemImage: state.isCaptureRunning || state.isCaptureStarting ? "stop.fill" : "record.circle"
                        )
                    }
                    .buttonStyle(.borderedProminent)

                    Text(state.isCaptureRunning ? "Running" : "Stopped")
                        .font(.caption)
                        .foregroundStyle(state.isCaptureRunning ? .green : .secondary)
                }

                Text(state.captureStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(state.proxyRoutingStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

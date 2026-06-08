import SwiftUI

@MainActor
@Observable
final class NetworkingSidebarState {
    var isDetached = false
    var isCaptureStarting = false
    var isCaptureStopping = false
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

            certificateSection

            Divider()

            proxyControllSection

            Divider()

            Text("Requests will appear here")
                .foregroundStyle(.secondary)

            Spacer()
        }
        .padding(.top, 16)
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: state.isDetached ? 0 : 18))
    }
    
    @ViewBuilder
    var background: some View {
        if state.isDetached {
            Rectangle()
                .fill(.regularMaterial)
        } else {
            RoundedRectangle(cornerRadius: 18)
                .fill(.regularMaterial)
        }
    }
    
    var certificateSection: some View {
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
    }
    
    var proxyControllSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button {
                    onCaptureToggled()
                } label: {
                    if isCaptureTransitioning {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)

                            Text(captureButtonTitle)
                        }
                    } else {
                        Label(
                            captureButtonTitle,
                            systemImage: captureButtonSystemImage
                        )
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isCaptureTransitioning)
                .accessibilityLabel(captureButtonTitle)

                Text(captureStatusTitle)
                    .font(.caption)
                    .foregroundStyle(captureStatusColor)
            }

            Text(state.captureStatus)
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(state.proxyRoutingStatus)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var isCaptureTransitioning: Bool {
        state.isCaptureStarting || state.isCaptureStopping
    }

    private var captureButtonTitle: String {
        if state.isCaptureStarting {
            return "Starting ..."
        }

        if state.isCaptureStopping {
            return "Stopping ..."
        }

        return state.isCaptureRunning ? "Stop" : "Start"
    }

    private var captureButtonSystemImage: String {
        state.isCaptureRunning ? "stop.fill" : "record.circle"
    }

    private var captureStatusTitle: String {
        if state.isCaptureStarting {
            return "Starting ..."
        }

        if state.isCaptureStopping {
            return "Stopping ..."
        }

        return state.isCaptureRunning ? "Running" : "Stopped"
    }

    private var captureStatusColor: Color {
        state.isCaptureRunning || state.isCaptureStarting || state.isCaptureStopping ? .green : .secondary
    }
}

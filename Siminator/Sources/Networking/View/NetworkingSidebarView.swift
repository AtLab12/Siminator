import AppKit
import SwiftUI

struct NetworkingSidebarView: View {
    @Bindable var viewModel: NetworkingSidebarVM
    @State private var isSessionBrowserPresented = false

    let onDetachedChanged: @MainActor (Bool) -> Void
    let onCaptureToggled: @MainActor () -> Void
    let onCertificateInstallRequested: @MainActor () -> Void

    var body: some View {
        VStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 14) {
                header
                Divider()
                certificateSection
                Divider()
                proxyControlSection
                Divider()
            }
            .padding(.horizontal, 16)
            
            sessionSection
        }
        .padding(.top, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: viewModel.isDetached ? 0 : 18))
    }

    private var header: some View {
        HStack(spacing: 10) {
            IconMaterialButton(
                systemImage: viewModel.isDetached ? "pin.fill" : "macwindow",
                accessibilityLabel: viewModel.isDetached ? "Dock to simulator" : "Detach window",
                action: {
                    onDetachedChanged(!viewModel.isDetached)
                }
            )

            Text("Networking")
                .font(.title2.weight(.semibold))
                .lineLimit(1)

            Spacer(minLength: 12)

            if !viewModel.isDetached {
                IconMaterialButton(
                    systemImage: "sidebar.right",
                    accessibilityLabel: "Show request details",
                    action: {}
                )
                .disabled(true)
                .help("Show request details")
            }
        }
    }
    
    @ViewBuilder
    var background: some View {
        if viewModel.isDetached {
            Rectangle()
                .fill(.regularMaterial)
        } else {
            RoundedRectangle(cornerRadius: 18)
                .fill(.regularMaterial)
        }
    }
    
    var certificateSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if viewModel.isCertificateTrusted {
                Label(viewModel.certificateStatus, systemImage: "checkmark.shield.fill")
                    .font(.callout)
                    .foregroundStyle(.green)
                    .lineLimit(2)
            } else {
                Button {
                    onCertificateInstallRequested()
                } label: {
                    Label("Trust Certificate", systemImage: "shield")
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isCertificateInstalling)

                if viewModel.isCertificateInstalling {
                    ProgressView()
                        .controlSize(.small)
                }

                Text(viewModel.certificateStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }
    
    var proxyControlSection: some View {
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

                Spacer()
                
                if viewModel.clearSessionButtonVisible {
                    Button {
                        withAnimation {
                            viewModel.clearSession()
                        }
                    } label: {
                        Label("Clear session", systemImage: "trash")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

            Text(viewModel.captureStatus)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Text(viewModel.proxyRoutingStatus)
                .font(.callout)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
    }

    private var sessionSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("Live session:")
                    .font(.headline)
                    .lineLimit(1)

                TextField("Session title", text: $viewModel.activeSession.title)
                    .textFieldStyle(.plain)
                    .font(.headline)
                    .lineLimit(1)

                Spacer(minLength: 8)

                IconMaterialButton(
                    systemImage: "list.bullet",
                    accessibilityLabel: "Past sessions",
                    action: {
                        isSessionBrowserPresented.toggle()
                    }
                )
                .popover(isPresented: $isSessionBrowserPresented, arrowEdge: .bottom) {
                    Text("Past sessions")
                        .font(.headline)
                        .padding(16)
                        .frame(width: 220, alignment: .leading)
                }
            }
            .padding(.horizontal, 16)

            if viewModel.totalRequestCount > viewModel.visibleRequests.count {
                Text("Showing latest \(viewModel.visibleRequests.count.formatted()) of \(viewModel.totalRequestCount.formatted())")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if viewModel.visibleRequests.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "network")
                        .font(.title2)
                        .foregroundStyle(.secondary)

                    Text("No requests captured")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack {
                        ForEach(viewModel.visibleRequests.reversed()) { request in
                            CapturedRequestRow(request: request)
                        }
                    }
                    .padding(.vertical)
                    .padding(.bottom)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var isCaptureTransitioning: Bool {
        viewModel.isCaptureStarting || viewModel.isCaptureStopping
    }

    private var captureButtonTitle: String {
        if viewModel.isCaptureStarting {
            return "Starting ..."
        }

        if viewModel.isCaptureStopping {
            return "Stopping ..."
        }

        return viewModel.isCaptureRunning ? "Stop" : "Start"
    }

    private var captureButtonSystemImage: String {
        viewModel.isCaptureRunning ? "stop.fill" : "record.circle"
    }

    private var captureStatusColor: Color {
        viewModel.isCaptureRunning || viewModel.isCaptureStarting || viewModel.isCaptureStopping ? .green : .secondary
    }
}

private struct IconMaterialButton: View {
    let systemImage: String
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 30, height: 30)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .background(.thinMaterial, in: Circle())
        .overlay {
            Circle()
                .strokeBorder(.white.opacity(0.2), lineWidth: 1)
        }
        .accessibilityLabel(accessibilityLabel)
    }
}

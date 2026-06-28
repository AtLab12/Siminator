import AppKit
import SwiftUI
import ComposableArchitecture

struct NetworkingFeatureView: View {
    let store: StoreOf<NetworkingFeature>
    
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

//            sessionSection
        }
        .padding(.top, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            Rectangle()
                .fill(.regularMaterial)
                .clipShape(RoundedRectangle(cornerRadius: store.isDetached ? 0 : 18))
        }
        .onAppear {
            store.send(.domain(.onAppear))
        }
    }
    
    private var header: some View {
        HStack(spacing: 10) {
            IconMaterialButton(
                systemImage: store.isDetached ? "pin.fill" : "macwindow",
                accessibilityLabel: store.isDetached ? "Dock to simulator" : "Detach window",
                action: {
                    store.send(.domain(.detachStatusToggled))
                }
            )

            Text("Networking")
                .font(.title2.weight(.semibold))
                .lineLimit(1)

            Spacer(minLength: 12)

            if !store.isDetached {
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
    
    private var certificateSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Root macOS certificate
            if store.rootCertificateStatus == .loading {
                ProgressView {
                    Text("Loading certificates ...")
                }
                .controlSize(.small)
            } else if store.rootCertificateStatus == .generated {
                Label(store.rootCertificateStatus.rawValue, systemImage: "checkmark.shield.fill")
                    .font(.callout)
                    .foregroundStyle(.green)
                    .lineLimit(2)
                    .contentTransition(.symbolEffect(.replace))
            } else {
                Button {
                    store.send(.domain(.generateRootCertificatePressed))
                } label: {
                    Label("Generate Certificate", systemImage: "shield")
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.bordered)
                .disabled(store.rootCertificateStatus == .generating)

                if store.rootCertificateStatus == .generating {
                    ProgressView()
                        .controlSize(.small)
                }

                Text(store.rootCertificateStatus.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if store.rootCertificateStatus != .loading {
                Button {
                    store.send(.domain(.installCertificateToSimPressed))
                } label: {
                    Label("Install certificate on simulator", systemImage: "iphone")
                }
                .buttonStyle(.bordered)
                .disabled(store.isInstallingCertToSim)
                //            .popover(isPresented: $viewModel.isSimulatorSelectionPopoverPresented) {
                //                simulatorSelection
                //            }
            }
        }
    }
    
    private var proxyControlSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Button {
//                    onCaptureToggled()
                } label: {
                    if store.isTransitioning {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)

                            Text(store.captureButtonTitle)
                        }
                    } else {
                        Label(
                            store.captureButtonTitle,
                            systemImage: captureButtonSystemImage
                        )
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.isTransitioning)
                .accessibilityLabel(store.captureButtonTitle)

                Spacer()

                if store.isClearSessionVisible {
                    Button {
                        withAnimation {
//                            viewModel.clearSession()
                        }
                    } label: {
                        Label("Clear session", systemImage: "trash")
                    }
                    .buttonStyle(.borderedProminent)
                }
            }

//            Text(viewModel.captureStatus)
//                .font(.caption)
//                .foregroundStyle(.secondary)
//                .lineLimit(2)
//
//            Text(viewModel.proxyRoutingStatus)
//                .font(.callout)
//                .foregroundStyle(.secondary)
//                .lineLimit(3)
        }
    }
    
    private var captureButtonSystemImage: String {
        store.captureStatus == .running ? "stop.fill" : "record.circle"
    }
}

struct NetworkingSidebarView: View {
    @Bindable var viewModel: NetworkingSidebarVM

    let onDetachedChanged: @MainActor (Bool) -> Void
    let onCaptureToggled: @MainActor () -> Void
    let onCertificateGenerationRequested: @MainActor () -> Void
    let onInstallCertificateOnSim: @MainActor () -> Void

    var body: some View {
        VStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 14) {
              
            }
            .padding(.horizontal, 16)

            sessionSection
        }
        .padding(.top, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: viewModel.isDetached ? 0 : 18))
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

    
    
    var simulatorSelection: some View {
        Group {
            if viewModel.bootedDevices.isEmpty {
                VStack {
                    ProgressView()
                    Text("Loading booted devices...")
                }
            } else {
                VStack(alignment: .leading) {
                    Text("Select simulator:")
                    Divider()
                    ForEach(viewModel.bootedDevices) { device in
                        HStack {
                            Button {
                                viewModel.simulatorSelectedWithId(device.udid)
                            } label: {
                                Text(device.name)
                            }
                            if let sim = viewModel.processingSim {
                                if device.udid == sim.udid {
                                    ProgressView()
                                        .scaleEffect(0.5)
                                } else if sim.requiresReboot {
                                    Button {
                                        // install on simulator action here
                                    } label: {
                                        Text("Reboot")
                                    }
                                }
                            }
                        }
                    }
                }
                .presentationSizing(.fitted)
            }
        }
        .padding()
    }

    private var sessionSection: some View {
        SessionLogView(viewModel: viewModel.sessionViewModel)
    }

    private var isCaptureTransitioning: Bool {
        viewModel.isCaptureStarting || viewModel.isCaptureStopping
    }

    
}

struct IconMaterialButton: View {
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

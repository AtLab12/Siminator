import ComposableArchitecture
import SwiftUI

struct NetworkingFeatureView: View {
    let store: StoreOf<NetworkingFeature>

    var body: some View {
        VStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 14) {
                header
                Divider()
                certificateSection
                Divider()
            }
            .padding(.horizontal, 16)

            NetworkingSessionView(store: store.scope(state: \.session, action: \.session))
        }
        .padding(.top, 16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            Rectangle()
                .fill(.regularMaterial)
                .clipShape(.rect(cornerRadius: store.isDetached ? 0 : 18))
        }
        .onAppear {
            store.send(.view(.onAppear))
        }
    }

    private var certificateSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            switch store.rootCertificateStatus {
            case .loading:
                ProgressView {
                    Text("Loading certificates ...")
                }
                .controlSize(.small)

            case .generated, .installed:
                Label(store.rootCertificateStatus.rawValue, systemImage: "checkmark.shield.fill")
                    .font(.callout)
                    .foregroundStyle(.green)
                    .lineLimit(2)
                    .contentTransition(.symbolEffect(.replace))

            case .installFailed, .rebootFailed:
                Text(store.rootCertificateStatus.rawValue)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(2)

            case .generating, .generationFailed, .requiresGenerating, .requiresInstalling:
                Button {
                    store.send(.view(.generateRootCertificatePressed))
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
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            IconMaterialButton(
                systemImage: store.isDetached ? "pin.fill" : "macwindow",
                accessibilityLabel: store.isDetached ? "Dock to simulator" : "Detach window",
                action: {
                    store.send(.view(.detachStatusToggled))
                }
            )

            Text("Networking")
                .font(.title2.weight(.semibold))
                .lineLimit(1)

            Spacer(minLength: 12)
        }
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

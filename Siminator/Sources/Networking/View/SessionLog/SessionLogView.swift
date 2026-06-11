import Foundation
import SwiftUI

struct SessionLogView: View {
    
    @Bindable var viewModel: SessionLogVM
    @State private var isSessionBrowserPresented = false
    @FocusState private var isSessionTitleFocused: Bool
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
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
                
                IconMaterialButton(systemImage: "wrench.and.screwdriver", accessibilityLabel: "Preview logging settings") {
                    viewModel.logginSettingsEnabled.toggle()
                }
                
                Spacer(minLength: 8)

                TextField("Session title", text: $viewModel.activeSession.title)
                    .textFieldStyle(.plain)
                    .font(.headline)
                    .lineLimit(1)
                    .focused($isSessionTitleFocused)
            }
            .padding(.horizontal, 16)
            .defaultFocus($isSessionTitleFocused, false)

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
}

#if DEBUG
#Preview {
    let requests = (1...5).map { i in
        CapturedNetworkRequest(
            id: UUID(),
            createdAt: Date(),
            method: "GET",
            host: "127.0.0.1",
            port: 9090,
            path: "https://example.com/apiv1/dogs",
            status: .succeeded,
            process: .unknown
        )
    }
    SessionLogView(viewModel: .init(requests: requests))
}
#endif


import Foundation
import SwiftUI

struct SessionLogView: View {
    @Bindable var viewModel: SessionLogVM
    @State private var isSessionBrowserPresented = false
    @State private var isAppFilterPresented = false
    @FocusState private var isSessionTitleFocused: Bool
    @FocusState private var isURLFilterFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            toolSection

            if viewModel.logginSettingsEnabled {
                advancedFiltering
            }

            if let requestSummary {
                Text(requestSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 16)
            }

            if viewModel.filteredRequests.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: viewModel.visibleRequests.isEmpty ? "network" : "magnifyingglass")
                        .font(.title2)
                        .foregroundStyle(.secondary)

                    Text(viewModel.visibleRequests.isEmpty ? "No requests captured" : "No matching requests")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack {
                        ForEach(viewModel.filteredRequests.reversed()) { request in
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

    // MARK: - Tool section

    var toolSection: some View {
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
    }

    // MARK: - Advanced filtering

    var advancedFiltering: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)

                TextField("Filter request URLs", text: $viewModel.urlFilterText)
                    .textFieldStyle(.plain)
                    .font(.callout)
                    .focused($isURLFilterFocused)

                if !viewModel.urlFilterText.isEmpty {
                    Button {
                        viewModel.urlFilterText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear URL filter")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .sessionLogGlassSurface(.rect(cornerRadius: 14), isInteractive: true)

            Button {
                isAppFilterPresented.toggle()
            } label: {
                HStack(spacing: 10) {
                    if let selectedAppFilter = viewModel.selectedAppFilter {
                        RequestProcessIcon(process: selectedAppFilter.process)
                            .frame(width: 22, height: 22)
                    } else {
                        Image(systemName: "square.grid.2x2")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 22, height: 22)
                    }

                    VStack(alignment: .leading, spacing: 1) {
                        Text(viewModel.selectedAppFilter?.displayName ?? "All Apps")
                            .font(.callout.weight(.medium))
                            .lineLimit(1)

                        Text("Filter by source app")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 8)

                    Image(systemName: "chevron.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .contentShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .sessionLogGlassSurface(.rect(cornerRadius: 14), isInteractive: true)
            .popover(isPresented: $isAppFilterPresented, arrowEdge: .bottom) {
                SessionLogAppFilterPopover(
                    appFilters: viewModel.appFilters,
                    selectedAppFilter: viewModel.selectedAppFilter
                ) { appFilter in
                    viewModel.selectedAppFilter = appFilter
                    isAppFilterPresented = false
                }
            }
        }
        .padding(.horizontal, 16)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    private var requestSummary: String? {
        if viewModel.logginSettingsEnabled, viewModel.hasActiveFilters {
            return "Showing \(viewModel.filteredRequests.count.formatted()) matching of \(viewModel.visibleRequests.count.formatted()) recent requests"
        }

        if viewModel.totalRequestCount > viewModel.visibleRequests.count {
            return "Showing latest \(viewModel.visibleRequests.count.formatted()) of \(viewModel.totalRequestCount.formatted())"
        }

        return nil
    }
}

private struct SessionLogAppFilterPopover: View {
    let appFilters: [SessionLogAppFilter]
    let selectedAppFilter: SessionLogAppFilter?
    let onSelect: (SessionLogAppFilter?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Requests From")
                .font(.headline)
                .padding(.horizontal, 12)
                .padding(.top, 12)

            VStack(spacing: 4) {
                Button {
                    onSelect(nil)
                } label: {
                    AppFilterRow(
                        title: "All Apps",
                        systemImage: "square.grid.2x2",
                        isSelected: selectedAppFilter == nil
                    )
                }
                .buttonStyle(.plain)

                Divider()
                    .padding(.horizontal, 12)

                if appFilters.isEmpty {
                    Text("No apps captured")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            ForEach(appFilters) { appFilter in
                                Button {
                                    onSelect(appFilter)
                                } label: {
                                    AppFilterRow(
                                        title: appFilter.displayName,
                                        process: appFilter.process,
                                        isSelected: selectedAppFilter == appFilter
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.bottom, 8)
                    }
                    .frame(maxHeight: 400)
                }
            }
        }
        .frame(width: 280)
        .padding(.bottom, 8)
    }
}

private struct AppFilterRow: View {
    let title: String
    let systemImage: String?
    let process: CapturedRequestProcess?
    let isSelected: Bool

    init(title: String, systemImage: String, isSelected: Bool) {
        self.title = title
        self.systemImage = systemImage
        process = nil
        self.isSelected = isSelected
    }

    init(title: String, process: CapturedRequestProcess, isSelected: Bool) {
        self.title = title
        systemImage = nil
        self.process = process
        self.isSelected = isSelected
    }

    var body: some View {
        HStack(spacing: 10) {
            if let process {
                RequestProcessIcon(process: process)
                    .frame(width: 24, height: 24)
            } else if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 24, height: 24)
            }

            Text(title)
                .font(.callout)
                .lineLimit(1)

            Spacer(minLength: 8)

            if isSelected {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.tint)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(.rect)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

private extension View {
    @ViewBuilder
    func sessionLogGlassSurface<S: InsettableShape>(_ shape: S, isInteractive: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            if isInteractive {
                glassEffect(.regular.interactive(), in: shape)
            } else {
                glassEffect(.regular, in: shape)
            }
        } else {
            background(.thinMaterial, in: shape)
                .overlay {
                    shape.strokeBorder(.white.opacity(0.18), lineWidth: 1)
                }
        }
    }
}

#if DEBUG
    #Preview {
        let requests = (1 ... 5).map { _ in
            CapturedNetworkRequest(
                id: UUID(),
                createdAt: Date(),
                method: "GET",
                scheme: "https",
                host: "127.0.0.1",
                port: 9090,
                path: "/apiv1/dogs",
                status: .succeeded,
                process: .unknown
            )
        }
        SessionLogView(viewModel: .init(requests: requests))
    }
#endif

import ComposableArchitecture
import SwiftUI

struct NetworkingSessionView: View {
    @Bindable var store: StoreOf<NetworkingSession>
    @FocusState private var isSessionTitleFocused: Bool
    @FocusState private var isURLFilterFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            toolbarSection
            captureStatusSection

            if store.settingsEnabled {
                advancedFiltering
            }

            requestSummarySection
            requestListSection
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task {
            await store.send(.requestEventsTask).finish()
        }
    }

    private var advancedFiltering: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)

                TextField("Filter request URLs", text: $store.urlFilterText)
                    .textFieldStyle(.plain)
                    .font(.callout)
                    .focused($isURLFilterFocused)

                if !store.urlFilterText.isEmpty {
                    Button {
                        store.send(.clearURLFilterButtonTapped)
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
                store.showAppFilter = true
            } label: {
                HStack(spacing: 10) {
                    appFilterIcon

                    VStack(alignment: .leading, spacing: 1) {
                        Text(store.selectedAppFilter?.displayName ?? "All Apps")
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
                .contentShape(.rect(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .sessionLogGlassSurface(.rect(cornerRadius: 14), isInteractive: true)
            .popover(isPresented: $store.showAppFilter, arrowEdge: .bottom) {
                SessionLogAppFilterPopover(
                    appFilters: store.appFilters,
                    selectedAppFilter: store.selectedAppFilter
                ) { appFilter in
                    store.send(.appFilterSelected(appFilter), animation: .default)
                }
            }
        }
        .padding(.horizontal, 16)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    @ViewBuilder
    private var appFilterIcon: some View {
        if let selectedAppFilter = store.selectedAppFilter {
            RequestProcessIcon(process: selectedAppFilter.process)
                .frame(width: 22, height: 22)
        } else {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
        }
    }

    private var captureStatusSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(store.captureStatusText)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            Text(store.proxyRoutingStatus)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .padding(.horizontal, 16)
    }

    @ViewBuilder
    private var requestListSection: some View {
        if store.filteredRequests.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: store.visibleRequests.isEmpty ? "network" : "magnifyingglass")
                    .font(.title2)
                    .foregroundStyle(.secondary)

                Text(store.visibleRequests.isEmpty ? "No requests captured" : "No matching requests")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack {
                    ForEach(store.filteredRequests.reversed()) { request in
                        CapturedRequestRow(request: request)
                    }
                }
                .padding(.vertical)
                .padding(.bottom)
            }
        }
    }

    @ViewBuilder
    private var requestSummarySection: some View {
        if let requestSummary = store.requestSummary {
            Text(requestSummary)
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
        }
    }

    private var toolbarSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                IconMaterialButton(
                    systemImage: "list.bullet",
                    accessibilityLabel: "Past sessions",
                    action: {
                        store.send(.sessionBrowserButtonTapped)
                    }
                )
                .popover(isPresented: $store.showSessionBrowser, arrowEdge: .bottom) {
                    Text("Past sessions")
                        .font(.headline)
                        .padding(16)
                        .frame(width: 220, alignment: .leading)
                }

                IconMaterialButton(
                    systemImage: "wrench.and.screwdriver",
                    accessibilityLabel: "Preview logging settings",
                    action: {
                        store.send(.settingsButtonTapped, animation: .easeIn)
                    }
                )

                Spacer(minLength: 8)

                TextField("Session title", text: $store.activeSessionTitle)
                    .textFieldStyle(.plain)
                    .font(.headline)
                    .lineLimit(1)
                    .focused($isSessionTitleFocused)
            }

            HStack(spacing: 8) {
                Button {
                    store.send(.captureButtonTapped)
                } label: {
                    if store.isCaptureTransitioning {
                        HStack(spacing: 6) {
                            ProgressView()
                                .controlSize(.small)

                            Text(store.captureButtonTitle)
                        }
                    } else {
                        Label(
                            store.captureButtonTitle,
                            systemImage: store.captureButtonSystemImage
                        )
                    }
                }
                .buttonStyle(.borderedProminent)
                .tint(.gray)
                .disabled(store.isCaptureTransitioning)
                .accessibilityLabel(store.captureButtonTitle)

                Spacer(minLength: 8)

                if store.isClearSessionVisible {
                    Button {
                        store.send(.clearSessionButtonTapped, animation: .default)
                    } label: {
                        Label("Clear session", systemImage: "trash")
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(.horizontal, 16)
        .defaultFocus($isSessionTitleFocused, false)
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
    func sessionLogGlassSurface<S: InsettableShape>(
        _ shape: S,
        isInteractive: Bool = false
    ) -> some View {
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

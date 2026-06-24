import AppKit
import SwiftUI
import ComposableArchitecture

@MainActor
final class NetworkingSidebarController: NSObject, NSWindowDelegate {
    private enum Layout {
        static let width: CGFloat = 360
        static let minimumDetachedHeight: CGFloat = 420
        static let cornerRadius: CGFloat = 18
    }

    private(set) var isNetworkingEnabled: Bool = false
    
    private let panel: SiminatorPanel
    private var simulatorFrame: CGRect?
    private var simulatorWindowNumber: Int?
    private var targetFrame: CGRect?
    private var movementTimer: Timer?
    private var detachedFrame: CGRect?
    private var shouldOrderOutAfterAnimation = false
//    private let appIconCache = AppIconCache()
    private(set) var isDetached: Bool = false
    
//    private lazy var appIconStore = AppIconStore(cache: appIconCache)
//    private let certificateMaterialManager = CertificateMaterialManager()
//    private lazy var proxyServer = LocalHTTPProxyServer(
//        appIconStore: appIconStore,
//        certificateMaterialManager: certificateMaterialManager
//    ) { [weak self] event in
////        self?.state.handleRequestEvent(event)
//    }

//    private let systemProxySettingsManager = SystemProxySettingsManager()
//    private var proxyControlTask: Task<Void, Never>?
//    private var certificateGenerationTask: Task<Void, Never>?
//    private var certInstallTask: Task<Void, Never>?
//    private var captureOperationID = 0
//    var onEnabledChanged: ((Bool) -> Void)?
    var onPanelInteraction: (() -> Void)?

    @MainActor
    override init() {
        panel = SiminatorPanel(
            contentRect: NSRect(x: 100, y: 100, width: Layout.width, height: 600),
            styleMask: [
                .borderless,
                .nonactivatingPanel,
            ],
            backing: .buffered,
            defer: false
        )

        super.init()

        panel.delegate = self
        
        configureDockedPanel()
//        refreshCertificateState()
    }

    func connect(store: StoreOf<NetworkingFeature>) {
        store.send(.connectController(self))
        
        let hostingView = NSHostingView(rootView: NetworkingFeatureView(store: store))
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor

        panel.contentView = hostingView
    }
    
    private func configureDockedPanel() {
        panel.onUserInteraction = { [weak self] in
            if !(self?.isDetached ?? true) {
                self?.onPanelInteraction?()
            }
        }
        
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isFloatingPanel = false
        panel.level = .normal
        panel.hidesOnDeactivate = false
        panel.styleMask = [
            .borderless,
            .nonactivatingPanel,
        ]
        panel.title = ""
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.minSize = NSSize(width: Layout.width, height: Layout.minimumDetachedHeight)
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary,
        ]
    }
    
    private func showIfPossible() {
        guard let simulatorFrame else { return }

        shouldOrderOutAfterAnimation = false

        if !panel.isVisible {
            panel.setFrame(hiddenFrame(for: simulatorFrame), display: false, animate: false)
            panel.orderFrontRegardless()
            orderBelowSimulatorWindow()
        }

        move(to: visibleFrame(for: simulatorFrame))
    }
    
    private func orderBelowSimulatorWindow() {
        guard !isDetached else { return }
        guard let simulatorWindowNumber, panel.isVisible else { return }
        panel.order(.below, relativeTo: simulatorWindowNumber)
    }
    
    private func hiddenFrame(for simulatorFrame: CGRect) -> CGRect {
        let screenFrame = SimulatorWindowGeometry.simulatorScreenFrame(from: simulatorFrame)

        return CGRect(
            x: screenFrame.minX + SimulatorWindowGeometry.gap,
            y: screenFrame.minY,
            width: Layout.width,
            height: screenFrame.height
        )
    }
    
    private func move(to frame: CGRect) {
        targetFrame = frame
        orderBelowSimulatorWindow()
        startMovementTimer()
    }
    
    private func visibleFrame(for simulatorFrame: CGRect) -> CGRect {
        let screenFrame = SimulatorWindowGeometry.simulatorScreenFrame(from: simulatorFrame)

        return CGRect(
            x: screenFrame.minX - SimulatorWindowGeometry.gap - Layout.width,
            y: screenFrame.minY,
            width: Layout.width,
            height: screenFrame.height
        )
    }
    

    func setEnabled(_ isEnabled: Bool) {
        self.isNetworkingEnabled = isEnabled
        if isEnabled {
            showIfPossible()
        } else {
            hide()
        }
    }

    func update(simulatorFrame: CGRect?, simulatorWindowNumber: Int?) {
        self.simulatorFrame = simulatorFrame
        self.simulatorWindowNumber = simulatorWindowNumber

        guard isNetworkingEnabled else { return }

        if isDetached {
            if !panel.isVisible {
                showDetachedWindow()
            }

            return
        }

        guard simulatorFrame != nil else {
            hideImmediately()
            return
        }

        showIfPossible()
    }
    
    private func hide() {
        if isDetached {
            detachedFrame = panel.frame
            hideImmediately()
            return
        }
        
        guard let simulatorFrame else {
            hideImmediately()
            return
        }
        
        guard panel.isVisible else { return }
        
        shouldOrderOutAfterAnimation = true
        move(to: hiddenFrame(for: simulatorFrame))
    }
    
//
//    func windowShouldClose(_: NSWindow) -> Bool {
//        setEnabled(false)
//        onEnabledChanged?(false)
//        return false
//    }
//
//    func bringToFrontWithSimulator() {
//        guard panel.isVisible else { return }
//
//        if state.isDetached {
//            panel.orderFrontRegardless()
//            panel.makeKey()
//        } else {
//            panel.orderFrontRegardless()
//            orderBelowSimulatorWindow()
//        }
//    }

    func setDetached(_ value: Bool) {
        guard self.isDetached != value else { return }
        self.isDetached = value
        
        if value {
            detachFromSimulator()
        } else {
            dockToSimulator()
        }
    }

    private func detachFromSimulator() {
        stopMovementTimer()
        targetFrame = nil
        shouldOrderOutAfterAnimation = false
        configureDetachedPanel()
        showDetachedWindow()
    }

    private func dockToSimulator() {
        detachedFrame = panel.frame
        configureDockedPanel()

        // TODO: - Handle this case
//        guard isEnabled else {
//            hideImmediately()
//            return
//        }

        guard simulatorFrame != nil else {
            hideImmediately()
            return
        }

        showIfPossible()
    }

    private func showDetachedWindow() {
        let currentFrame = panel.frame
        let frame = detachedFrame ?? CGRect(
            x: currentFrame.minX,
            y: currentFrame.minY,
            width: max(currentFrame.width, Layout.width),
            height: max(currentFrame.height, Layout.minimumDetachedHeight)
        )

        panel.setFrame(frame, display: true, animate: false)
        panel.orderFrontRegardless()
        panel.makeKey()
    }

    private func configureDetachedPanel() {
        panel.styleMask = [
            .titled,
            .closable,
            .miniaturizable,
            .resizable
        ]
        panel.titleVisibility = .visible
        panel.titlebarAppearsTransparent = false
        panel.titlebarSeparatorStyle = .shadow
        panel.toolbarStyle = .automatic
        panel.isMovable = true
        panel.isMovableByWindowBackground = false
        panel.minSize = NSSize(width: Layout.width, height: Layout.minimumDetachedHeight)
        panel.collectionBehavior = []
    }

    private func hideImmediately() {
        stopMovementTimer()
        targetFrame = nil
        shouldOrderOutAfterAnimation = false
        panel.orderOut(nil)
    }

    private func startMovementTimer() {
        guard movementTimer == nil else { return }

        let timer = Timer(timeInterval: 1.0 / SiminatorConst.refreshRate, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.moveTowardTargetFrame()
            }
        }

        timer.tolerance = 0
        RunLoop.main.add(timer, forMode: .common)
        movementTimer = timer
    }

    private func stopMovementTimer() {
        movementTimer?.invalidate()
        movementTimer = nil
    }

    private func moveTowardTargetFrame() {
        guard let targetFrame else {
            stopMovementTimer()
            return
        }

        let currentFrame = panel.frame

        guard !currentFrame.isClose(to: targetFrame) else {
            panel.setFrame(targetFrame, display: true, animate: false)
            stopMovementTimer()

            if shouldOrderOutAfterAnimation {
                shouldOrderOutAfterAnimation = false
                panel.orderOut(nil)
            }

            return
        }

        let nextFrame = currentFrame.interpolated(to: targetFrame, amount: 0.3)
        panel.setFrame(nextFrame, display: true, animate: false)
        orderBelowSimulatorWindow()
    }
//
//
//    private func toggleCapture() {
//        guard !state.isCaptureStarting, !state.isCaptureStopping else {
//            return
//        }
//
//        if state.isCaptureRunning {
//            stopCapture()
//        } else {
//            startCapture()
//        }
//    }
//
//    private func startCapture() {
//        guard proxyControlTask == nil else { return }
//
//        captureOperationID += 1
//        let operationID = captureOperationID
//
//        state.isCaptureStarting = true
//        state.isCaptureStopping = false
//        state.captureStatus = "Starting proxy on \(ProxyConstants.host):\(ProxyConstants.port)"
//        state.beginNewSession()
//
//        proxyControlTask = Task { [weak self] in
//            guard let self else { return }
//
//            do {
//                try await refreshCertificateState()
//                guard isCurrentCaptureOperation(operationID) else { return }
//
//                if !state.isCertificateGenerated {
//                    let didGenerateCertificate = await performCertificateGenerationFlow()
//                    guard isCurrentCaptureOperation(operationID) else { return }
//
//                    guard didGenerateCertificate else {
//                        state.captureStatus = "Proxy start cancelled"
//                        state.isCaptureStarting = false
//                        state.isCaptureStopping = false
//                        proxyControlTask = nil
//                        return
//                    }
//                }
//
//                let port = try await proxyServer.start(port: ProxyConstants.port)
//                guard isCurrentCaptureOperation(operationID) else { return }
//
//                state.isCaptureRunning = true
//                state.isCaptureStarting = false
//                state.captureStatus = "Listening on \(ProxyConstants.host):\(port)"
//                state.proxyRoutingStatus = "Enabling system proxy"
//
//                let services = try await systemProxySettingsManager.enableProxy(host: ProxyConstants.host, port: port)
//                guard isCurrentCaptureOperation(operationID) else { return }
//
//                state.captureStatus = "Listening on \(ProxyConstants.host):\(port)"
//                state.proxyRoutingStatus = "Routing enabled: \(services.joined(separator: ", "))"
//            } catch {
//                guard isCurrentCaptureOperation(operationID) else { return }
//
//                if state.isCaptureRunning {
//                    state.proxyRoutingStatus = "System proxy failed: \(error.localizedDescription)"
//                } else {
//                    state.captureStatus = "Failed to start proxy: \(error.localizedDescription)"
//                    state.proxyRoutingStatus = "System proxy disabled"
//                    try? await proxyServer.stop()
//                }
//            }
//
//            if isCurrentCaptureOperation(operationID) {
//                state.isCaptureStarting = false
//                state.isCaptureStopping = false
//                proxyControlTask = nil
//            }
//        }
//    }
//
//    func refreshCertificateState() {
//        Task { [weak self] in
//            guard let self else { return }
//            try? await refreshCertificateState()
//        }
//    }
//
//    func deleteCertificates() {
//        Task { [weak self] in
//            guard let self else { return }
//
//            do {
//                try await certificateMaterialManager.deleteCertificateMaterial()
//                state.isCertificateGenerated = false
//                state.isCertificateGenerating = false
//                state.certificateStatus = .requiresGenerating
//            } catch {
//                state.certificateStatus = .generationFailed
//            }
//        }
//    }
//
//    private func refreshCertificateState() async throws {
//        let certificateState = try await certificateMaterialManager.certificateState()
//        state.isCertificateGenerated = certificateState.isGenerated
//
//        if certificateState.isGenerated {
//            state.certificateStatus = .generated
//        } else {
//            state.certificateStatus = .requiresGenerating
//        }
//    }
//
//    private func stopCapture() {
//        guard !state.isCaptureStopping else { return }
//
//        captureOperationID += 1
//        let inFlightStartTask = proxyControlTask
//        inFlightStartTask?.cancel()
//        state.isCaptureStopping = true
//        state.isCaptureStarting = false
//        state.captureStatus = "Stopping proxy"
//
//        proxyControlTask = Task { [weak self] in
//            guard let self else { return }
//
//            // An in-flight enableProxy XPC call is not interrupted by cancellation;
//            // wait for it so restore runs after the proxy was actually enabled.
//            await inFlightStartTask?.value
//
//            do {
//                try await systemProxySettingsManager.restoreProxySettings()
//                try await proxyServer.stop()
//                state.captureStatus = "Proxy stopped"
//                state.proxyRoutingStatus = "System proxy restored"
//            } catch {
//                state.captureStatus = "Failed to stop proxy: \(error.localizedDescription)"
//            }
//
//            state.isCaptureStarting = false
//            state.isCaptureStopping = false
//            state.isCaptureRunning = false
//            proxyControlTask = nil
//        }
//    }
//
//    private func isCurrentCaptureOperation(_ operationID: Int) -> Bool {
//        captureOperationID == operationID && !Task.isCancelled
//    }
//
//    @discardableResult
//    private func performCertificateGenerationFlow() async -> Bool {
//        guard confirmCertificateGeneration() else {
//            state.certificateStatus = .requiresGenerating
//            return false
//        }
//
//        state.isCertificateGenerating = true
//        state.certificateStatus = .generating
//
//        do {
//            _ = try await certificateMaterialManager.ensureCertificateMaterialExists()
//            state.isCertificateGenerated = true
//            state.certificateStatus = .generated
//            state.isCertificateGenerating = false
//            return true
//        } catch {
//            state.isCertificateGenerated = false
//            state.certificateStatus = .generationFailed
//            state.isCertificateGenerating = false
//            return false
//        }
//    }
//
//    private func requestCertificateGeneration() {
//        guard certificateGenerationTask == nil else { return }
//
//        certificateGenerationTask = Task { [weak self] in
//            guard let self else { return }
//            _ = await performCertificateGenerationFlow()
//            certificateGenerationTask = nil
//        }
//    }
//
//    private func confirmCertificateGeneration() -> Bool {
//        let alert = NSAlert()
//        alert.messageText = "Generate Siminator Root Certificate?"
//        alert.informativeText = """
//        Siminator needs a local root certificate and private key to decrypt and display HTTPS traffic. Both files are generated on this Mac and stored together in Application Support.
//        """
//        alert.alertStyle = .warning
//        alert.addButton(withTitle: "Generate")
//        alert.addButton(withTitle: "Cancel")
//
//        NSApp.activate()
//        return alert.runModal() == .alertFirstButtonReturn
//    }
//}
//
//extension NetworkingSidebarController {
//    private func selectSimulator() {
//        state.isSimulatorSelectionPopoverPresented = true
//        state.isInstallingOnSimulator = true
//
//        do {
////            state.bootedDevices = try certificateMaterialManager.getBootedSimulators()
//            state.isInstallingOnSimulator = false
//        } catch {
//            state.isInstallingOnSimulator = false
//        }
//    }
//
//    private func installCertificateOnSelectedSimulator(udid: String) {
//        guard certInstallTask == nil else { return }
//
////        certInstallTask = Task { [weak self] in
////            guard let self else { return }
////
////            do {
////                try await certificateMaterialManager.installRootCertToSimulator(udid: udid)
////                state.processingSim?.requiresReboot = true
////            } catch {
////                print(error)
////            }
////
////            certInstallTask = nil
////        }
//    }
}

private extension CGRect {
    func isClose(to other: CGRect) -> Bool {
        let distanceThreshold: CGFloat = 3.0
        return abs(origin.x - other.origin.x) <= distanceThreshold
            && abs(origin.y - other.origin.y) <= distanceThreshold
            && abs(size.width - other.size.width) <= distanceThreshold
            && abs(size.height - other.size.height) <= distanceThreshold
    }

    func interpolated(to other: CGRect, amount: CGFloat) -> CGRect {
        CGRect(
            x: origin.x + (other.origin.x - origin.x) * amount,
            y: origin.y + (other.origin.y - origin.y) * amount,
            width: size.width + (other.size.width - size.width) * amount,
            height: size.height + (other.size.height - size.height) * amount
        )
    }
}

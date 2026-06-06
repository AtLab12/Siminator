import AppKit
import SwiftUI

@MainActor
final class NetworkingSidebarController: NSObject, NSWindowDelegate {
    private enum Layout {
        static let width: CGFloat = 360
        static let minimumDetachedHeight: CGFloat = 420
        static let cornerRadius: CGFloat = 18
    }

    private let panel: NSPanel
    private let state = NetworkingSidebarState()
    private var simulatorFrame: CGRect?
    private var simulatorWindowNumber: Int?
    private var targetFrame: CGRect?
    private var movementTimer: Timer?
    private var isEnabled = false
    private var detachedFrame: CGRect?
    private var shouldOrderOutAfterAnimation = false
    private let proxyServer = LocalHTTPProxyServer()
    private let certificateTrustManager = CertificateTrustManager()
    private let systemProxySettingsManager = SystemProxySettingsManager()
    private var proxyControlTask: Task<Void, Never>?
    private var certificateInstallTask: Task<Void, Never>?
    var onEnabledChanged: (@MainActor (Bool) -> Void)?

    override init() {
        panel = NSPanel(
            contentRect: NSRect(x: 100, y: 100, width: Layout.width, height: 600),
            styleMask: [
                .borderless,
                .nonactivatingPanel
            ],
            backing: .buffered,
            defer: false
        )

        super.init()

        panel.delegate = self
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isFloatingPanel = false
        panel.level = .normal
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary
        ]

        let hostingView = NSHostingView(
            rootView: NetworkingSidebarView(
                state: state,
                onDetachedChanged: { [weak self] isDetached in
                    self?.setDetached(isDetached)
                },
                onCaptureToggled: { [weak self] in
                    self?.toggleCapture()
                },
                onCertificateInstallRequested: { [weak self] in
                    self?.requestCertificateInstall()
                }
            )
        )
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor

        panel.contentView = hostingView
        configureDockedPanel()
        refreshCertificateTrustState()
    }

    func setEnabled(_ isEnabled: Bool) {
        guard self.isEnabled != isEnabled else { return }
        self.isEnabled = isEnabled

        if isEnabled {
            showIfPossible()
        } else {
            hide()
        }
    }

    func update(simulatorFrame: CGRect?, simulatorWindowNumber: Int?) {
        self.simulatorFrame = simulatorFrame
        self.simulatorWindowNumber = simulatorWindowNumber

        guard isEnabled else { return }

        if state.isDetached {
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

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        setEnabled(false)
        onEnabledChanged?(false)
        return false
    }

    private func setDetached(_ isDetached: Bool) {
        guard state.isDetached != isDetached else { return }
        state.isDetached = isDetached

        if isDetached {
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

        guard isEnabled else {
            hideImmediately()
            return
        }

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

    private func configureDockedPanel() {
        panel.styleMask = [
            .borderless,
            .nonactivatingPanel
        ]
        panel.title = ""
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.minSize = NSSize(width: Layout.width, height: Layout.minimumDetachedHeight)
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary
        ]
    }

    private func configureDetachedPanel() {
        panel.styleMask = [
            .titled,
            .closable,
            .miniaturizable,
            .resizable
        ]
        panel.title = "Networking"
        panel.titleVisibility = .visible
        panel.titlebarAppearsTransparent = false
        panel.isMovable = true
        panel.isMovableByWindowBackground = false
        panel.minSize = NSSize(width: Layout.width, height: Layout.minimumDetachedHeight)
        panel.collectionBehavior = []
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

    private func hide() {
        if state.isDetached {
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

    private func hideImmediately() {
        stopMovementTimer()
        targetFrame = nil
        shouldOrderOutAfterAnimation = false
        panel.orderOut(nil)
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

    private func startMovementTimer() {
        guard movementTimer == nil else { return }

        let timer = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
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

    private func orderBelowSimulatorWindow() {
        guard !state.isDetached else { return }
        guard let simulatorWindowNumber, panel.isVisible else { return }
        panel.order(.below, relativeTo: simulatorWindowNumber)
    }

    private func toggleCapture() {
        if state.isCaptureRunning || state.isCaptureStarting {
            stopCapture()
        } else {
            startCapture()
        }
    }

    private func startCapture() {
        guard proxyControlTask == nil else { return }

        state.isCaptureStarting = true
        state.captureStatus = "Starting proxy on 127.0.0.1:9090"

        proxyControlTask = Task { [weak self] in
            guard let self else { return }

            do {
                try await refreshCertificateTrustState()

                if !state.isCertificateTrusted {
                    let didInstallCertificate = await performCertificateInstallFlow()
                    guard didInstallCertificate else {
                        state.captureStatus = "Proxy start cancelled"
                        state.isCaptureStarting = false
                        proxyControlTask = nil
                        return
                    }
                }

                let port = try await proxyServer.start(port: 9090)
                state.proxyPort = port

                guard confirmSystemProxyEnable(port: port) else {
                    try await proxyServer.stop()
                    state.captureStatus = "Proxy start cancelled"
                    state.proxyRoutingStatus = "System proxy disabled"
                    state.isCaptureStarting = false
                    proxyControlTask = nil
                    return
                }

                let services = try await systemProxySettingsManager.enableProxy(host: "127.0.0.1", port: port)
                state.isCaptureRunning = true
                state.captureStatus = "Listening on 127.0.0.1:\(port)"
                state.proxyRoutingStatus = "Routing enabled: \(services.joined(separator: ", "))"
            } catch {
                state.captureStatus = "Failed to start proxy: \(error.localizedDescription)"
                state.proxyRoutingStatus = "System proxy disabled"
                try? await proxyServer.stop()
            }

            state.isCaptureStarting = false
            proxyControlTask = nil
        }
    }

    private func refreshCertificateTrustState() {
        Task { [weak self] in
            guard let self else { return }
            try? await refreshCertificateTrustState()
        }
    }

    private func refreshCertificateTrustState() async throws {
        let trustState = try await certificateTrustManager.trustState()
        state.isCertificateTrusted = trustState.isTrusted

        if trustState.isTrusted {
            state.certificateStatus = "Trusted: \(trustState.certificateURL?.lastPathComponent ?? "Siminator Root CA")"
        } else if trustState.certificateURL != nil {
            state.certificateStatus = "Certificate generated but not trusted"
        } else {
            state.certificateStatus = "Certificate not trusted"
        }
    }

    private func stopCapture() {
        proxyControlTask?.cancel()
        proxyControlTask = Task { [weak self] in
            guard let self else { return }

            do {
                try await systemProxySettingsManager.restoreProxySettings()
                try await proxyServer.stop()
                state.captureStatus = "Proxy stopped"
                state.proxyRoutingStatus = "System proxy restored"
            } catch {
                state.captureStatus = "Failed to stop proxy: \(error.localizedDescription)"
            }

            state.isCaptureStarting = false
            state.isCaptureRunning = false
            proxyControlTask = nil
        }
    }

    @discardableResult
    private func performCertificateInstallFlow() async -> Bool {
        guard confirmCertificateTrust() else {
            state.certificateStatus = "Certificate trust cancelled"
            return false
        }

        state.isCertificateInstalling = true
        state.certificateStatus = "Installing certificate in login keychain"

        do {
            let certificateURL = try await certificateTrustManager.installTrustedRootCertificate()
            state.isCertificateTrusted = true
            state.certificateStatus = "Trusted: \(certificateURL.lastPathComponent)"
            state.isCertificateInstalling = false
            return true
        } catch {
            state.isCertificateTrusted = false
            state.certificateStatus = "Certificate install failed: \(error.localizedDescription)"
            state.isCertificateInstalling = false
            return false
        }
    }

    private func requestCertificateInstall() {
        guard certificateInstallTask == nil else { return }

        certificateInstallTask = Task { [weak self] in
            guard let self else { return }
            _ = await performCertificateInstallFlow()
            certificateInstallTask = nil
        }
    }

    private func confirmCertificateTrust() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Trust Siminator Root Certificate?"
        alert.informativeText = """
        Siminator needs a local root certificate to decrypt and display HTTPS traffic. The certificate and private key are generated on this Mac and stored in your user Application Support folder.

        macOS will add this certificate as trusted for your login keychain. Only continue if you want Siminator to inspect HTTPS traffic from this Mac.
        """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Trust and Install")
        alert.addButton(withTitle: "Cancel")

        NSApp.activate()
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func confirmSystemProxyEnable(port: Int) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Route Mac Traffic Through Siminator?"
        alert.informativeText = """
        Siminator needs to update macOS Web Proxy and Secure Web Proxy settings so apps send HTTP and HTTPS traffic to 127.0.0.1:\(port).

        macOS may ask for an administrator password. Siminator will restore the previous proxy settings when capture stops.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Enable Proxy")
        alert.addButton(withTitle: "Cancel")

        NSApp.activate()
        return alert.runModal() == .alertFirstButtonReturn
    }
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

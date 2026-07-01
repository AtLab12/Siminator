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
    private(set) var isDetached: Bool = false

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
    }

    func connect(store: StoreOf<NetworkingFeature>) {
        store.send(.connectController(self))
        
        let hostingView = NSHostingView(
            rootView: NetworkingFeatureView(store: store)
                .environment(AppIconCache.shared)
        )
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
    
    func windowShouldClose(_: NSWindow) -> Bool {
        setEnabled(false)
        return false
    }

    func bringToFrontWithSimulator() {
        guard panel.isVisible else { return }

        if isDetached {
            panel.orderFrontRegardless()
            panel.makeKey()
        } else {
            panel.orderFrontRegardless()
            orderBelowSimulatorWindow()
        }
    }

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

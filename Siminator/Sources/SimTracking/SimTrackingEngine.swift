import AppKit

struct SimulatorWindowSnapshot: Sendable {
    let frame: CGRect
    let windowNumber: Int
}

@MainActor
final class SimTrackingEngine {
    var onSimulatorFrameChanged: (@MainActor (SimulatorWindowSnapshot?) -> Void)?

    private var simulatorPID: pid_t?
    private var pollingTimer: Timer?
    private var lastPublishedSnapshot: SimulatorWindowSnapshot?
    private var didPublishMissingSimulator = false
    private var didRegisterWorkspaceObservers = false

    func start() {
        registerWorkspaceObserversIfNeeded()
        attachToSimulatorIfRunning()
    }

    private func registerWorkspaceObserversIfNeeded() {
        guard !didRegisterWorkspaceObservers else { return }
        didRegisterWorkspaceObservers = true

        let nc = NSWorkspace.shared.notificationCenter

        nc.addObserver(
            self,
            selector: #selector(applicationsChanged),
            name: NSWorkspace.didLaunchApplicationNotification,
            object: nil
        )

        nc.addObserver(
            self,
            selector: #selector(applicationsChanged),
            name: NSWorkspace.didTerminateApplicationNotification,
            object: nil
        )

        nc.addObserver(
            self,
            selector: #selector(applicationsChanged),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }

    @objc private func applicationsChanged() {
        attachToSimulatorIfRunning()
    }

    private func attachToSimulatorIfRunning() {
        guard let app = findSimulatorApplication() else {
            simulatorPID = nil
            stopPolling()
            publishSimulatorWindow(nil)
            return
        }

        simulatorPID = app.processIdentifier
        startPolling()
        updateSimulatorFrame()
    }

    private func findSimulatorApplication() -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first {
            $0.bundleIdentifier == "com.apple.iphonesimulator"
            || $0.localizedName == "Simulator"
        }
    }

    private func updateSimulatorFrame() {
        guard let simulatorPID, let snapshot = frontmostSimulatorWindowSnapshot(for: simulatorPID) else {
            publishSimulatorWindow(nil)
            return
        }

        publishSimulatorWindow(snapshot)
    }

    private func frontmostSimulatorWindowSnapshot(for processIdentifier: pid_t) -> SimulatorWindowSnapshot? {
        guard let windowInfo = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        for window in windowInfo {
            guard
                numberValue(for: kCGWindowOwnerPID, in: window)?.int32Value == processIdentifier,
                numberValue(for: kCGWindowLayer, in: window)?.intValue == 0,
                (numberValue(for: kCGWindowAlpha, in: window)?.doubleValue ?? 1) > 0,
                let windowNumber = numberValue(for: kCGWindowNumber, in: window)?.intValue,
                let boundsDictionary = window[kCGWindowBounds as String] as? [String: Any],
                let bounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary),
                bounds.width > 100,
                bounds.height > 100
            else {
                continue
            }

            return SimulatorWindowSnapshot(
                frame: convertCGTopLeftToAppKitBottomLeft(bounds),
                windowNumber: windowNumber
            )
        }

        return nil
    }

    private func startPolling() {
        guard pollingTimer == nil else { return }

        let timer = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateSimulatorFrame()
            }
        }

        timer.tolerance = 0
        RunLoop.main.add(timer, forMode: .common)
        pollingTimer = timer
    }

    private func stopPolling() {
        pollingTimer?.invalidate()
        pollingTimer = nil
    }

    private func publishSimulatorWindow(_ snapshot: SimulatorWindowSnapshot?) {
        guard let snapshot else {
            lastPublishedSnapshot = nil

            guard !didPublishMissingSimulator else { return }
            didPublishMissingSimulator = true
            onSimulatorFrameChanged?(nil)
            return
        }

        didPublishMissingSimulator = false

        if let lastPublishedSnapshot,
           lastPublishedSnapshot.windowNumber == snapshot.windowNumber,
           lastPublishedSnapshot.frame.isClose(to: snapshot.frame) { return }

        lastPublishedSnapshot = snapshot
        onSimulatorFrameChanged?(snapshot)
    }

    // Minor helper to keep code readable
    private func numberValue(
        for key: CFString,
        in window: [String: Any]
    ) -> NSNumber? {
        window[key as String] as? NSNumber
    }

    // Appkit conversoin helper
    private func convertCGTopLeftToAppKitBottomLeft(_ bounds: CGRect) -> CGRect {
        guard let screenMatch = screenMatch(for: bounds) else {
            let screenUnion = NSScreen.screens
                .map(\.frame)
                .reduce(CGRect.null) { $0.union($1) }

            return CGRect(
                x: bounds.origin.x,
                y: screenUnion.maxY - bounds.origin.y - bounds.height,
                width: bounds.width,
                height: bounds.height
            )
        }

        return CGRect(
            x: screenMatch.screen.frame.minX + bounds.minX - screenMatch.displayBounds.minX,
            y: screenMatch.screen.frame.maxY - (bounds.minY - screenMatch.displayBounds.minY) - bounds.height,
            width: bounds.width,
            height: bounds.height
        )
    }

    // Finds which physical display contains the Simulator window
    private func screenMatch(for bounds: CGRect) -> (screen: NSScreen, displayBounds: CGRect)? {
        NSScreen.screens
            .compactMap { screen -> (screen: NSScreen, displayBounds: CGRect, overlapArea: CGFloat)? in
                guard
                    let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
                else {
                    return nil
                }

                let displayBounds = CGDisplayBounds(CGDirectDisplayID(displayID.uint32Value))
                let intersection = displayBounds.intersection(bounds)

                guard !intersection.isNull else { return nil }
                return (
                    screen: screen,
                    displayBounds: displayBounds,
                    overlapArea: intersection.width * intersection.height
                )
            }
            .max { $0.overlapArea < $1.overlapArea }
            .map { (screen: $0.screen, displayBounds: $0.displayBounds) }
    }
}

// Filters out tiny CoreGraphics frame noise so unchanged Simulator positions. Do not publish redundant panel updates.
private extension CGRect {
    func isClose(to other: CGRect) -> Bool {
        abs(origin.x - other.origin.x) < 0.5
            && abs(origin.y - other.origin.y) < 0.5
            && abs(size.width - other.size.width) < 0.5
            && abs(size.height - other.size.height) < 0.5
    }
}

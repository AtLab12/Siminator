import AppKit
import ApplicationServices

struct SimulatorWindowSnapshot: Sendable {
    let frame: CGRect
    let windowNumber: Int
    let simulatorUDID: String?
}

enum SiminatorConst {
    // Pooling refresh rate. 30Hz seems like the sweetspot
    static let refreshRate = 30.0
}

@MainActor
final class SimTrackingEngine {
    var onSimulatorFrameChanged: (@MainActor (SimulatorWindowSnapshot?) -> Void)?

    private var simulatorPID: pid_t?
    private var pollingTimer: Timer?
    private var lastPublishedSnapshot: SimulatorWindowSnapshot?
    private var lastResolvedSimulatorWindowNumber: Int?
    private var lastResolvedSimulatorWindowName: String?
    private var lastResolvedSimulatorUDID: String?
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
            resetResolvedSimulatorCache()
            stopPolling()
            publishSimulatorWindow(nil)
            return
        }

        if simulatorPID != app.processIdentifier {
            resetResolvedSimulatorCache()
        }

        simulatorPID = app.processIdentifier
        startPolling()
        updateSimulatorFrame()
    }

    private func findSimulatorApplication() -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == "com.apple.iphonesimulator" || $0.localizedName == "Simulator" }
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

            print(window[kCGWindowName as String] as? String)
            
//            let windowName = windowTitle(for: processIdentifier, matching: bounds)

            
            
            return SimulatorWindowSnapshot(
                frame: convertCGTopLeftToAppKitBottomLeft(bounds),
                windowNumber: windowNumber,
                simulatorUDID: simulatorUDID(
                    forWindowNumber: windowNumber,
                    windowName: "windowName"
                )
            )
        }

        return nil
    }

    private func startPolling() {
        guard pollingTimer == nil else { return }

        let timer = Timer(timeInterval: 1.0 / SiminatorConst.refreshRate, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.updateSimulatorFrame()
            }
        }

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
           lastPublishedSnapshot.frame.isClose(to: snapshot.frame),
           lastPublishedSnapshot.simulatorUDID == snapshot.simulatorUDID { return }

        lastPublishedSnapshot = snapshot
        onSimulatorFrameChanged?(snapshot)
    }

    private func simulatorUDID(
        forWindowNumber windowNumber: Int,
        windowName: String?
    ) -> String? {
        if lastResolvedSimulatorWindowNumber == windowNumber,
           lastResolvedSimulatorWindowName == windowName
        {
            return lastResolvedSimulatorUDID
        }

        let udid = bootedSimulatorUDID(matchingWindowName: windowName)
        lastResolvedSimulatorWindowNumber = windowNumber
        lastResolvedSimulatorWindowName = windowName
        lastResolvedSimulatorUDID = udid
        return udid
    }

    private func resetResolvedSimulatorCache() {
        lastResolvedSimulatorWindowNumber = nil
        lastResolvedSimulatorWindowName = nil
        lastResolvedSimulatorUDID = nil
    }

    private func bootedSimulatorUDID(matchingWindowName windowName: String?) -> String? {
        guard
            let output = try? ExecutableHelper().runExecutable(
                "/usr/bin/xcrun",
                arguments: ["simctl", "list", "devices", "booted", "--json"]
            ),
            let data = output.data(using: .utf8),
            let deviceList = try? JSONDecoder().decode(SimctlDeviceList.self, from: data)
        else {
            return nil
        }

        print(lastResolvedSimulatorWindowName)

        let bootedDevices = deviceList.bootedDevices

        if let windowName, !windowName.isEmpty {
            if let device = bootedDevice(matchingWindowName: windowName, in: bootedDevices) {
                return device.udid
            }
        }

        // If there is only one booted device, the visible Simulator window can
        // only belong to that device. Multiple booted devices must be resolved
        // by the attached window name above.
        return bootedDevices.count == 1 ? bootedDevices[0].udid : nil
    }

    private func bootedDevice(
        matchingWindowName windowName: String,
        in bootedDevices: [SimctlDevice]
    ) -> SimctlDevice? {
        let exactMatches = bootedDevices.filter { $0.name == windowName }
        if exactMatches.count == 1 {
            return exactMatches[0]
        }

        let containedMatches = bootedDevices
            .filter { windowName.localizedCaseInsensitiveContains($0.name) }
            .sorted { $0.name.count > $1.name.count }

        guard let bestMatch = containedMatches.first else {
            return nil
        }

        let equallySpecificMatches = containedMatches.filter {
            $0.name.count == bestMatch.name.count
        }

        return equallySpecificMatches.count == 1 ? bestMatch : nil
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

private struct SimctlDeviceList: Decodable {
    let devices: [String: [SimctlDevice]]

    var bootedDevices: [SimctlDevice] {
        devices.values.flatMap { $0 }.filter { $0.state == "Booted" }
    }
}

private struct SimctlDevice: Decodable {
    let name: String
    let udid: String
    let state: String
}

// Filters out tiny CoreGraphics frame noise so unchanged Simulator positions. Do not publish redundant panel updates.
private extension CGRect {
    func isClose(to other: CGRect) -> Bool {
        abs(origin.x - other.origin.x) < 0.5
            && abs(origin.y - other.origin.y) < 0.5
            && abs(size.width - other.size.width) < 0.5
            && abs(size.height - other.size.height) < 0.5
    }

    func maxAbsoluteDelta(to other: CGRect) -> CGFloat {
        max(
            abs(origin.x - other.origin.x),
            abs(origin.y - other.origin.y),
            abs(size.width - other.size.width),
            abs(size.height - other.size.height)
        )
    }
}

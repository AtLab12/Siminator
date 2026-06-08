import SwiftUI

@main
struct SiminatorApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Siminator", systemImage: "star") {
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            
            Button {
                appDelegate.refreshCertificate()
            } label: {
                Label {
                    Text("Refresh Certificate")
                } icon: {
                    Image(systemName: "arrow.trianglehead.counterclockwise")
                }
            }
        }

        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let panelController = SimTrackingController()
    private let networkingSidebarController = NetworkingSidebarController()
    private let tracker = SimTrackingEngine()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        panelController.onNetworkingEnabledChanged = { [weak self] isEnabled in
            self?.networkingSidebarController.setEnabled(isEnabled)
        }

        networkingSidebarController.onEnabledChanged = { [weak self] isEnabled in
            self?.panelController.setNetworkingEnabled(isEnabled)
        }

        panelController.onPanelInteraction = { [weak self] in
            self?.bringSimulatorWorkspaceToFront()
        }

        networkingSidebarController.onPanelInteraction = { [weak self] in
            self?.bringSimulatorWorkspaceToFront()
        }

        tracker.onSimulatorFrameChanged = { [weak self] snapshot in
            guard let self else { return }

            if let snapshot {
                let frame = snapshot.frame

                self.panelController.show()
                self.panelController.dock(
                    to: frame,
                    simulatorWindowNumber: snapshot.windowNumber
                )
                self.networkingSidebarController.update(
                    simulatorFrame: frame,
                    simulatorWindowNumber: snapshot.windowNumber
                )
            } else {
                self.panelController.hide()
                self.networkingSidebarController.update(
                    simulatorFrame: nil,
                    simulatorWindowNumber: nil
                )
            }
        }

        tracker.start()
    }

    private func bringSimulatorWorkspaceToFront() {
        activateSimulatorIfRunning()
        bringSiminatorPanelsToFront()

        DispatchQueue.main.async { [weak self] in
            self?.bringSiminatorPanelsToFront()
        }
    }

    private func activateSimulatorIfRunning() {
        guard let simulator = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == "com.apple.iphonesimulator" || $0.localizedName == "Simulator"
        }) else {
            return
        }

        simulator.activate(options: [.activateAllWindows])
    }

    private func bringSiminatorPanelsToFront() {
        panelController.bringToFrontWithSimulator()
        networkingSidebarController.bringToFrontWithSimulator()
    }
    
    func refreshCertificate() {
        self.networkingSidebarController.refreshCertificateTrustState()
    }
}

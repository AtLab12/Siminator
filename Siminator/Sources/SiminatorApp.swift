import SwiftUI
import ComposableArchitecture

@main
struct SiminatorApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    
    static let store = Store(initialState: SiminatorController.State()) {
        SiminatorController()
    }
    
    var body: some Scene {
        MenuBarExtra("Siminator", systemImage: "star") {
            Button("Quit") {
                SiminatorApp.store.send(.extraMenu(.quit))
            }

            Button {
                SiminatorApp.store.send(.extraMenu(.refreshCertificate))
            } label: {
                Label {
                    Text("Refresh Certificate")
                } icon: {
                    Image(systemName: "arrow.trianglehead.counterclockwise")
                }
            }

            Button {
                SiminatorApp.store.send(.extraMenu(.deleteCertificates))
            } label: {
                Label {
                    Text("Delete Certificates")
                } icon: {
                    Image(systemName: "trash")
                }
            }
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let panelController = SimTrackingController()
    private let networkingSidebarController = NetworkingSidebarController()
    private let tracker = SimTrackingEngine()

    func applicationDidFinishLaunching(_: Notification) {
        NSApp.setActivationPolicy(.accessory)
        
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(workspaceDidActivateApplication),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )

        networkingSidebarController.connect(
            store: SiminatorApp.store.scope(\.networking, action: \.networking)
        )

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

    @objc private func workspaceDidActivateApplication(_ notification: Notification) {
        guard
            let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
            isSimulator(application)
        else {
            return
        }

        bringSiminatorPanelsToFront()

        DispatchQueue.main.async { [weak self] in
            self?.bringSiminatorPanelsToFront()
        }
    }

    private func bringSimulatorWorkspaceToFront() {
        activateSimulatorIfRunning()
        bringSiminatorPanelsToFront()

        DispatchQueue.main.async { [weak self] in
            self?.bringSiminatorPanelsToFront()
        }
    }

    private func activateSimulatorIfRunning() {
        guard let simulator = NSWorkspace.shared.runningApplications.first(where: isSimulator) else {
            return
        }

        simulator.activate(options: [.activateAllWindows])
    }

    private func isSimulator(_ application: NSRunningApplication) -> Bool {
        application.bundleIdentifier == "com.apple.iphonesimulator"
            || application.localizedName == "Simulator"
    }

    private func bringSiminatorPanelsToFront() {
        panelController.bringToFrontWithSimulator()
        networkingSidebarController.bringToFrontWithSimulator()
    }
}

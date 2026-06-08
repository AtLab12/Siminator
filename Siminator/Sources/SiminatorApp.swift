import SwiftUI

@main
struct SiminatorApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("Siminator", systemImage: "star") {
            Button("Quit Siminator") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
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
}

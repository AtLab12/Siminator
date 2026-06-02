import SwiftUI

@main
struct SiminatorApp: App {
    
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    
    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let panelController = SimTrackingController()
    private let tracker = SimTrackingEngine()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        tracker.onSimulatorFrameChanged = { [weak self] frame in
            guard let self else { return }

            if let frame {
                self.panelController.show()
                self.panelController.dock(to: frame)
            } else {
                self.panelController.hide()
            }
        }

        tracker.start()
    }
}

import Foundation
import AppKit
import SwiftUI

final class SimTrackingController {
    private enum Layout {
        static let size = CGSize(width: 260, height: 180)
        static let gap: CGFloat = 10
        static let simulatorScreenOffset: CGFloat = 65
    }

    private let panel: NSPanel
    private var targetFrame: CGRect?
    private var movementTimer: Timer?

    init() {
        panel = NSPanel(
            contentRect: NSRect(
                x: 100,
                y: 100,
                width: Layout.size.width,
                height: Layout.size.height
            ),
            styleMask: [
                .borderless,
                .nonactivatingPanel
            ],
            backing: .buffered,
            defer: false
        )

        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .fullScreenAuxiliary
        ]

        let hostingView = NSHostingView(
            rootView: ToolsHomeView()
                .frame(width: Layout.size.width, height: Layout.size.height)
        )
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor

        panel.contentView = hostingView
    }

    func show() {
        guard !panel.isVisible else { return }
        panel.orderFrontRegardless()
    }

    func hide() {
        stopMovementTimer()
        targetFrame = nil
        panel.orderOut(nil)
    }

    func dock(to simulatorFrame: CGRect) {
        var frame = panel.frame

        frame.origin.x = simulatorFrame.maxX + Layout.gap
        frame.origin.y = simulatorFrame.maxY - frame.height - Layout.simulatorScreenOffset

        let screen = NSScreen.screens.first { $0.visibleFrame.intersects(simulatorFrame) } ?? NSScreen.main

        if let visible = screen?.visibleFrame {
            if frame.maxX > visible.maxX {
                frame.origin.x = simulatorFrame.minX - Layout.gap - frame.width
            }

            frame.origin.y = min(frame.origin.y, visible.maxY - frame.height)
            frame.origin.y = max(frame.origin.y, visible.minY)
        }

        if targetFrame == nil {
            targetFrame = frame
            panel.setFrame(frame, display: true, animate: false)
            return
        }

        targetFrame = frame
        startMovementTimer()
    }

    private func startMovementTimer() {
        guard movementTimer == nil else { return }

        // Track at 120Hz for smooth visual
        let timer = Timer(timeInterval: 1.0 / 120.0, repeats: true) { [weak self] _ in
            self?.moveTowardTargetFrame()
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
            return
        }

        let delta = currentFrame.maxAbsoluteDelta(to: targetFrame)
        
        // Smoothing and improving efficiency of the window travel path
        let nextFrame = delta > 240 ? targetFrame : currentFrame.interpolated(to: targetFrame, amount: 0.4)

        panel.setFrame(nextFrame, display: true, animate: false)
    }
}

// Keeps the panel-following math local to the controller instead of spreading
// small geometry helpers through the window movement code.
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

    func interpolated(to other: CGRect, amount: CGFloat) -> CGRect {
        CGRect(
            x: origin.x + (other.origin.x - origin.x) * amount,
            y: origin.y + (other.origin.y - origin.y) * amount,
            width: size.width + (other.size.width - size.width) * amount,
            height: size.height + (other.size.height - size.height) * amount
        )
    }
}

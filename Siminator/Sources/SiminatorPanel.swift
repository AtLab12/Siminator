//
//  SiminatorPanel.swift
//  Siminator
//
//  Created by Mikolaj Zawada on 06/06/2026.
//

import AppKit

@MainActor
final class SiminatorPanel: NSPanel {
    var onUserInteraction: (@MainActor () -> Void)?

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown
            || event.type == .rightMouseDown
            || event.type == .otherMouseDown {
            onUserInteraction?()
        }

        super.sendEvent(event)
    }
}

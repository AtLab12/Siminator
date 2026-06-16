import AppKit

enum SimulatorWindowGeometry {
    static let gap: CGFloat = 10
    static let screenTopInset: CGFloat = 65

    static func simulatorScreenFrame(from simulatorFrame: CGRect) -> CGRect {
        CGRect(
            x: simulatorFrame.minX,
            y: simulatorFrame.minY,
            width: simulatorFrame.width,
            height: max(0, simulatorFrame.height - screenTopInset)
        )
    }
}

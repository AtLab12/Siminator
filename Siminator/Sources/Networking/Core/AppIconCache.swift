import CoreGraphics
import SwiftUI

/// Main-actor cache of ready-to-render app icons keyed by bundle identifier.
///
/// `Image` values are created once per bundle identifier from a pre-downsampled
/// `CGImage`, so request rows pay only a dictionary lookup at render time.
@Observable
final class AppIconCache: @unchecked Sendable {
    static let shared = AppIconCache()

    private struct Style {
        static let displayScale: CGFloat = 2
    }

    private(set) var icons: [String: Image] = [:]

    func icon(for bundleID: String?) -> Image? {
        guard let bundleID else { return nil }
        return icons[bundleID]
    }

    func setIcon(_ cgImage: CGImage, for bundleID: String) {
        icons[bundleID] = Image(decorative: cgImage, scale: Style.displayScale)
    }
}

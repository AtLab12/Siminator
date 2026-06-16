import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Extracts, downsamples and persists app icons keyed by bundle identifier.
/// Extraction runs at most once per bundle identifier per app lifetime.
actor AppIconStore {
    private enum Constants {
        static let maxPixelSize = 64
        static let iconsSubdirectory = "Siminator/Icons"
    }

    private let cache: AppIconCache
    private let iconsDirectory: URL
    private var processedBundleIDs: Set<String> = []

    init(cache: AppIconCache) {
        self.cache = cache

        let baseDirectory = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? FileManager.default.temporaryDirectory
        iconsDirectory = baseDirectory.appendingPathComponent(
            Constants.iconsSubdirectory,
            isDirectory: true
        )
    }

    func ensureIcon(for app: ResolvedApp) async {
        guard let bundleID = app.bundleID, processedBundleIDs.insert(bundleID).inserted else {
            return
        }

        if let persisted = Self.downsampledImage(
            at: iconURL(for: bundleID),
            maxPixelSize: Constants.maxPixelSize
        ) {
            await publish(persisted, bundleID: bundleID)
            return
        }

        guard let icon = await extractIcon(for: app) else {
            return
        }

        persist(icon, bundleID: bundleID)
        await publish(icon, bundleID: bundleID)
    }

    // MARK: - Extraction

    private func extractIcon(for app: ResolvedApp) async -> CGImage? {
        let bundleURL = Self.bundleURL(forExecutablePath: app.path)

        if let bundleURL, let icon = bundleIcon(at: bundleURL) {
            return icon
        }

        let iconPath = (bundleURL ?? URL(fileURLWithPath: app.path)).path
        return await MainActor.run {
            Self.workspaceIcon(forPath: iconPath)
        }
    }

    /// Locates the enclosing `.app` bundle for an executable path. Covers both
    /// simulator layouts (`MyApp.app/MyApp`) and macOS layouts
    /// (`MyApp.app/Contents/MacOS/MyApp`).
    private static func bundleURL(forExecutablePath path: String) -> URL? {
        guard !path.isEmpty else { return nil }

        var url = URL(fileURLWithPath: path)
        while url.pathComponents.count > 1 {
            url.deleteLastPathComponent()
            if url.pathExtension == "app" {
                return url
            }
        }
        return nil
    }

    /// Reads the primary icon PNG directly from the bundle root
    private func bundleIcon(at bundleURL: URL) -> CGImage? {
        guard let bundle = Bundle(url: bundleURL) else { return nil }

        var iconNames: [String] = []
        if let icons = bundle.object(forInfoDictionaryKey: "CFBundleIcons") as? [String: Any],
           let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
           let files = primary["CFBundleIconFiles"] as? [String] {
            iconNames = files.reversed()
        }
        if let legacyFiles = bundle.object(forInfoDictionaryKey: "CFBundleIconFiles") as? [String] {
            iconNames.append(contentsOf: legacyFiles.reversed())
        }

        let fileManager = FileManager.default
        for name in iconNames {
            for suffix in ["@3x.png", "@2x.png", ".png", ""] {
                let candidate = bundleURL.appendingPathComponent(name + suffix)
                guard fileManager.fileExists(atPath: candidate.path) else { continue }

                if let icon = Self.downsampledImage(at: candidate, maxPixelSize: Constants.maxPixelSize) {
                    return icon
                }
            }
        }
        return nil
    }

    /// Fallback for host macOS apps and bare executables.
    @MainActor
    private static func workspaceIcon(forPath path: String) -> CGImage? {
        guard FileManager.default.fileExists(atPath: path) else { return nil }

        let icon = NSWorkspace.shared.icon(forFile: path)
        return rasterize(icon, pixelSize: Constants.maxPixelSize)
    }

    // MARK: - Image processing

    private static func downsampledImage(at url: URL, maxPixelSize: Int) -> CGImage? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else {
            return nil
        }

        let thumbnailOptions: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary)
    }

    @MainActor
    private static func rasterize(_ image: NSImage, pixelSize: Int) -> CGImage? {
        guard let context = CGContext(
            data: nil,
            width: pixelSize,
            height: pixelSize,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        let graphicsContext = NSGraphicsContext(cgContext: context, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = graphicsContext
        image.draw(
            in: NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize),
            from: .zero,
            operation: .copy,
            fraction: 1
        )
        NSGraphicsContext.restoreGraphicsState()

        return context.makeImage()
    }

    // MARK: - Persistence

    private func iconURL(for bundleID: String) -> URL {
        iconsDirectory.appendingPathComponent("\(bundleID).png", isDirectory: false)
    }

    private func persist(_ image: CGImage, bundleID: String) {
        do {
            try FileManager.default.createDirectory(at: iconsDirectory, withIntermediateDirectories: true)
        } catch {
            return
        }

        let url = iconURL(for: bundleID)
        guard let destination = CGImageDestinationCreateWithURL(
            url as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        ) else {
            return
        }

        CGImageDestinationAddImage(destination, image, nil)
        CGImageDestinationFinalize(destination)
    }

    private func publish(_ image: CGImage, bundleID: String) async {
        await MainActor.run { [cache] in
            cache.setIcon(image, for: bundleID)
        }
    }
}

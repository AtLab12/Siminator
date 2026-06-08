//
//  CapturedRequestRow.swift
//  Siminator
//
//  Created by Mikolaj Zawada on 08/06/2026.
//

import Foundation
import SwiftUI

struct CapturedRequestRow: View {
    let request: CapturedNetworkRequest

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(request.displayURL)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)

                HStack(spacing: 6) {
                    Text(request.method.uppercased())
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(statusColor)

                    Text(request.host)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 8)

            RequestProcessIcon(process: request.process)
                .frame(width: 28, height: 28)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(.white.opacity(0.18), lineWidth: 1)
        }
        .padding(.horizontal, 16)
        .shadow(color: statusColor.opacity(0.55), radius: 7, x: 0, y: 3)
    }

    private var statusColor: Color {
        switch request.status {
        case .inProgress:
            return .orange
        case .succeeded:
            return .green
        case .failed:
            return .red
        }
    }
}

private struct RequestProcessIcon: View {
    let process: CapturedRequestProcess

    var body: some View {
        if let image = appIcon {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            Image(systemName: "terminal")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 28, height: 28)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 6))
        }
    }

    private var appIcon: NSImage? {
        if let bundleIdentifier = process.bundleIdentifier,
           let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            return NSWorkspace.shared.icon(forFile: appURL.path)
        }

        if let executablePath = process.executablePath,
           FileManager.default.fileExists(atPath: executablePath) {
            return NSWorkspace.shared.icon(forFile: executablePath)
        }

        return nil
    }
}

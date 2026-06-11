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

struct RequestProcessIcon: View {
    private struct Style {
        static let cornerRadius: CGFloat = 6
        static let fallbackSymbolSize: CGFloat = 18
        static let fallbackSide: CGFloat = 28
    }

    @Environment(AppIconCache.self) private var iconCache

    let process: CapturedRequestProcess

    var body: some View {
        if let icon = iconCache.icon(for: process.bundleIdentifier) {
            icon
                .resizable()
                .scaledToFit()
                .clipShape(RoundedRectangle(cornerRadius: Style.cornerRadius))
        } else {
            Image(systemName: "terminal")
                .font(.system(size: Style.fallbackSymbolSize, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: Style.fallbackSide, height: Style.fallbackSide)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: Style.cornerRadius))
        }
    }
}

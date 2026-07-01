import Foundation
import SwiftUI

struct CapturedRequestRow: View {
    let request: CapturedNetworkRequest
    let isExpanded: Bool
    let showsDetachButton: Bool
    let onToggle: () -> Void
    let onDetach: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: onToggle) {
                rowHeader
                    .contentShape(.rect(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Show request details")

            if isExpanded {
                CapturedRequestSummary(
                    request: request,
                    showsDetachButton: showsDetachButton,
                    onDetach: onDetach
                )
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background {
            RoundedRectangle(cornerRadius: 16)
                .fill(.regularMaterial)
                .shadow(color: statusColor.opacity(0.55), radius: isExpanded ? 12 : 7, x: 0, y: 3)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(.white.opacity(0.18), lineWidth: 1)
        }
        .padding(.horizontal, 16)
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: isExpanded)
    }

    private var rowHeader: some View {
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

private struct CapturedRequestSummary: View {
    let request: CapturedNetworkRequest
    let showsDetachButton: Bool
    let onDetach: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            DetailSummaryRow(title: "Method:", value: request.method.uppercased())
            DetailSummaryRow(title: "Status:", value: request.status.detailText)
            DetailSummaryRow(title: "Time:", value: request.startedAt.networkingSummaryTime)
            DetailSummaryRow(title: "Duration:", value: request.durationText)
            DetailSummaryRow(title: "Request size:", value: request.byteCounts.requestBytes.byteCountText)
            DetailSummaryRow(title: "Response size:", value: request.byteCounts.responseBytes.byteCountText)

            if showsDetachButton {
                Button(action: onDetach) {
                    Text("Detach to preview details")
                        .font(.callout)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background {
                            Capsule()
                                .fill(.thinMaterial)
                                .shadow(color: .black.opacity(0.2), radius: 4, x: 0, y: 2)
                        }
                        .overlay {
                            Capsule()
                                .strokeBorder(.white.opacity(0.18), lineWidth: 1)
                        }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Detach to preview details")
                .padding(.top, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .font(.callout)
        .foregroundStyle(.primary)
        .animation(.spring(response: 0.28, dampingFraction: 0.86), value: showsDetachButton)
    }
}

private struct DetailSummaryRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .frame(width: 92, alignment: .leading)
            Text(value)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}

private extension CapturedNetworkRequest {
    var durationText: String {
        guard let completedAt else {
            return "In progress"
        }

        let milliseconds = max(1, Int((completedAt.timeIntervalSince(startedAt) * 1000).rounded()))
        return "\(milliseconds) ms"
    }
}

private extension Int {
    var byteCountText: String {
        ByteCountFormatter.string(fromByteCount: Int64(self), countStyle: .file)
    }
}

private extension CapturedRequestStatus {
    var detailText: String {
        switch self {
        case .inProgress:
            return "In progress"
        case .succeeded:
            return "Succeeded"
        case .failed:
            return "Failed"
        }
    }
}

private extension Date {
    var networkingSummaryTime: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter.string(from: self)
    }
}

struct RequestProcessIcon: View {
    private enum Style {
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

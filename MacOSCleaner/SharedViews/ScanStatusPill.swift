import SwiftUI

/// Compact freshness indicator shown in workspace headers when cached scan data exists.
struct ScanStatusPill: View {
    let lastUpdatedAt: Date?

    var body: some View {
        if let lastUpdatedAt {
            TimelineView(.periodic(from: .now, by: 30)) { context in
                let relative = Self.formatRelative(from: lastUpdatedAt, to: context.date)
                Label(String(format: "scan_updated_at".localized, relative), systemImage: "clock")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.secondary.opacity(0.10)))
                    .lineLimit(1)
            }
        }
    }

    private static func formatRelative(from date: Date, to now: Date) -> String {
        if now.timeIntervalSince(date) < 10 {
            return "scan_updated_just_now".localized
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.locale = LanguageManager.shared.currentLocale
        return formatter.localizedString(for: date, relativeTo: now)
    }
}

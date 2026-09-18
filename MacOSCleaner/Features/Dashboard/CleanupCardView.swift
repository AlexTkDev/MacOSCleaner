// Copyright (C) 2026 AlexTkDev
// Licensed under GNU General Public License v3.0 (GPLv3)

import SwiftUI

public struct CleanupCardView: View {
    public let record: CleanupRecord
    
    private var dateString: String {
        record.date.formatted(.dateTime.day().month(.abbreviated).year().locale(LanguageManager.shared.currentLocale))
    }
    
    private var timeString: String {
        record.date.formatted(.dateTime.hour().minute().locale(LanguageManager.shared.currentLocale))
    }
    
    public init(record: CleanupRecord) {
        self.record = record
    }
    
    public var body: some View {
        HStack(spacing: 12) {
            Image(systemName: record.category.iconName)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.accentColor)
                .frame(width: 28, height: 28)
                .glassEffect(Glass.regular.tint(.accentColor), in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            
            VStack(alignment: .leading, spacing: 2) {
                Text(dateString)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                Text(timeString)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer(minLength: 8)
            
            Text(record.formattedSize)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.green)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.04))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [Color.white.opacity(0.22), Color.white.opacity(0.06)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: Color.black.opacity(0.25), radius: 8, x: 0, y: 3)
    }
}

#Preview {
    CleanupCardView(
        record: CleanupRecord(
            freedBytes: 17_280_000_000,
            trigger: .manual,
            category: .general
        )
    )
    .frame(width: 250)
    .padding()
}

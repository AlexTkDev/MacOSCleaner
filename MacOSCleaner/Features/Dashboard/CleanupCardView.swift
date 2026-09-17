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
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(.secondary)
                .frame(width: 24, height: 24)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(dateString)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                
                Text(timeString)
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer(minLength: 8)
            
            Text(record.formattedSize)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.green)
                .lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
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

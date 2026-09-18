// Copyright (C) 2026 AlexTkDev
// Licensed under GNU General Public License v3.0 (GPLv3)

import SwiftUI

public enum HistorySortOption: String, CaseIterable, Identifiable {
    case date = "date"
    case size = "size"
    
    public var id: String { rawValue }
    
    public var localizedTitle: String {
        switch self {
        case .date:
            return "history_sort_date".localized
        case .size:
            return "history_sort_size".localized
        }
    }
}

public struct CleanupHistoryView: View {
    private let journal: TransactionJournal
    
    @State private var records: [CleanupRecord] = []
    @State private var searchText: String = ""
    @State private var sortOption: HistorySortOption = .date
    @State private var sortAscending: Bool = false
    @State private var isLoading: Bool = true
    
    public init(journal: TransactionJournal = TransactionJournal()) {
        self.journal = journal
    }
    
    public var filteredAndSortedRecords: [CleanupRecord] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = records.filter { record in
            if query.isEmpty { return true }
            let dateStr = record.date.formatted(.dateTime.day().month(.abbreviated).year().locale(LanguageManager.shared.currentLocale)).lowercased()
            let timeStr = record.date.formatted(.dateTime.hour().minute().locale(LanguageManager.shared.currentLocale)).lowercased()
            let sizeStr = record.formattedSize.lowercased()
            let triggerStr = record.trigger.localizedTitle.lowercased()
            let categoryStr = record.category.localizedTitle.lowercased()
            return dateStr.contains(query) || timeStr.contains(query) || sizeStr.contains(query) || triggerStr.contains(query) || categoryStr.contains(query)
        }
        
        return filtered.sorted { a, b in
            switch sortOption {
            case .date:
                return sortAscending ? a.date < b.date : a.date > b.date
            case .size:
                return sortAscending ? a.freedBytes < b.freedBytes : a.freedBytes > b.freedBytes
            }
        }
    }
    
    public var body: some View {
        ZStack {
            VisualEffectView(material: .underWindowBackground, blendingMode: .behindWindow)
                .opacity(0.85)
                .background(Color.black.opacity(0.20))
                .ignoresSafeArea()
            
            // Subtle ambient lighting
            GeometryReader { proxy in
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.08))
                        .frame(width: 260, height: 260)
                        .blur(radius: 60)
                        .offset(x: proxy.size.width * 0.2, y: -60)
                }
            }
            .allowsHitTesting(false)
            
            VStack(spacing: 0) {
                // Header / Search & Filter bar
                HStack(spacing: 10) {
                    HStack(spacing: 6) {
                        Image(systemName: "magnifyingglass")
                            .foregroundColor(.secondary)
                            .font(.system(size: 13))
                        
                        TextField("history_search_placeholder".localized, text: $searchText)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13))
                        
                        if !searchText.isEmpty {
                            Button {
                                searchText = ""
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                                    .font(.system(size: 12))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .glassEffect(Glass.regular, in: RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.white.opacity(0.12), lineWidth: 0.5)
                    )
                    
                    Menu {
                        ForEach(HistorySortOption.allCases) { option in
                            Button {
                                sortOption = option
                            } label: {
                                HStack {
                                    Text(option.localizedTitle)
                                    if sortOption == option {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(sortOption.localizedTitle)
                                .font(.system(size: 12, weight: .medium))
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 10))
                        }
                    }
                    .secondaryGlassButtonStyle()
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 8)
                
                // Subheader: Sort direction toggle
                HStack {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            sortAscending.toggle()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text(sortOption.localizedTitle)
                                .font(.system(size: 12, weight: .medium))
                            Image(systemName: sortAscending ? "chevron.up" : "chevron.down")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .onHover { inside in
                        if inside {
                            NSCursor.pointingHand.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                    
                    Spacer()
                    
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
                
                Divider()
                    .opacity(0.15)
                
                // Content List
                if isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if filteredAndSortedRecords.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "clock")
                            .font(.system(size: 36))
                            .foregroundColor(.secondary.opacity(0.5))
                        
                        Text("history_empty_state".localized)
                            .font(.system(size: 14))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(filteredAndSortedRecords) { record in
                                HistoryRowView(record: record)
                                Divider()
                                    .overlay(Color.white.opacity(0.05))
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .frame(minWidth: 450, idealWidth: 480, minHeight: 550, idealHeight: 600)
        .navigationTitle("history_window_title".localized)
        .task {
            await loadRecords()
        }
    }
    
    private func loadRecords() async {
        isLoading = true
        do {
            let transactions = try await journal.loadAll()
            records = transactions.reversed().map { CleanupRecord(transaction: $0) }
        } catch {
            records = []
        }
        isLoading = false
    }
}

public struct HistoryRowView: View {
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
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.accentColor.opacity(0.22), lineWidth: 0.5)
                    )
                Image(systemName: record.category.iconName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.accentColor)
            }
            .frame(width: 30, height: 30)
            
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
            
            Spacer(minLength: 12)
            
            HStack(spacing: 8) {
                Text(record.formattedSize)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.green)
                    .lineLimit(1)
                
                Text(record.trigger.localizedTitle)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.white.opacity(0.06))
                    .clipShape(Capsule())
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }
}

#Preview {
    CleanupHistoryView()
}

// Copyright (C) 2026 AlexTkDev
// SPDX-License-Identifier: LicenseRef-MacOSCleaner-GPLv3-Commons-NC
// Licensed under GNU GPLv3 with Commons Clause v1.0 & Non-Commercial Condition (see LICENSE).

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

private struct HistoryEntry: Identifiable {
    let record: CleanupRecord
    let operations: [OperationRecord]
    var id: UUID { record.id }
}

public struct CleanupHistoryView: View {
    private let journal: TransactionJournal
    
    @State private var entries: [HistoryEntry] = []
    @State private var searchText: String = ""
    @State private var sortOption: HistorySortOption = .date
    @State private var sortAscending: Bool = false
    @State private var isLoading: Bool = true
    
    public init(journal: TransactionJournal = TransactionJournal()) {
        self.journal = journal
    }
    
    private var filteredAndSortedEntries: [HistoryEntry] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let filtered = entries.filter { entry in
            let record = entry.record
            if query.isEmpty { return true }
            let dateStr = record.date.formatted(.dateTime.day().month(.abbreviated).year().locale(LanguageManager.shared.currentLocale)).lowercased()
            let timeStr = record.date.formatted(.dateTime.hour().minute().locale(LanguageManager.shared.currentLocale)).lowercased()
            let sizeStr = record.formattedSize.lowercased()
            let triggerStr = record.trigger.localizedTitle.lowercased()
            let categoryStr = record.category.localizedTitle.lowercased()
            let opsMatch = entry.operations.contains { $0.itemPath.lowercased().contains(query) }
            return dateStr.contains(query) || timeStr.contains(query) || sizeStr.contains(query) || triggerStr.contains(query) || categoryStr.contains(query) || opsMatch
        }
        
        return filtered.sorted { a, b in
            switch sortOption {
            case .date:
                return sortAscending ? a.record.date < b.record.date : a.record.date > b.record.date
            case .size:
                return sortAscending ? a.record.freedBytes < b.record.freedBytes : a.record.freedBytes > b.record.freedBytes
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
                } else if filteredAndSortedEntries.isEmpty {
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
                            ForEach(filteredAndSortedEntries) { entry in
                                HistoryRowView(record: entry.record, operations: entry.operations)
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
            entries = transactions.reversed().map { tx in
                HistoryEntry(record: CleanupRecord(transaction: tx), operations: tx.operations)
            }
        } catch {
            entries = []
        }
        isLoading = false
    }
}

public struct HistoryRowView: View {
    public let record: CleanupRecord
    public let operations: [OperationRecord]
    @State private var isExpanded = false
    
    private var dateString: String {
        record.date.formatted(.dateTime.day().month(.abbreviated).year().locale(LanguageManager.shared.currentLocale))
    }
    
    private var timeString: String {
        record.date.formatted(.dateTime.hour().minute().locale(LanguageManager.shared.currentLocale))
    }

    private var summaryModeTitle: String? {
        let modes = Set(operations.compactMap(\.deletionMode))
        guard !modes.isEmpty else { return nil }
        if modes.count > 1 { return "history_mode_mixed".localized }
        return modes.first == OperationRecord.DeletionMode.permanent.rawValue
            ? "history_mode_permanent".localized
            : "history_mode_trash".localized
    }

    private var totalSkipped: Int {
        operations.reduce(0) { $0 + ($1.skipped ?? 0) }
    }

    private var totalFailed: Int {
        operations.reduce(0) { $0 + ($1.failed ?? 0) }
    }
    
    public init(record: CleanupRecord, operations: [OperationRecord] = []) {
        self.record = record
        self.operations = operations
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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
                    HStack(spacing: 6) {
                        Text(dateString)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.primary)
                            .lineLimit(1)

                        Text("• \(record.category.localizedTitle)")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    
                    HStack(spacing: 6) {
                        Text(timeString)
                            .font(.system(size: 11, weight: .regular))
                            .foregroundColor(.secondary)
                            .lineLimit(1)

                        if let modeTitle = summaryModeTitle {
                            Text(modeTitle)
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.secondary)
                        }

                        if totalFailed > 0 {
                            Text("history_ops_failed_format".localizedWithArgs(Int64(totalFailed)))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.orange)
                        } else if totalSkipped > 0 {
                            Text("history_ops_skipped_format".localizedWithArgs(Int64(totalSkipped)))
                                .font(.system(size: 10, weight: .medium))
                                .foregroundColor(.secondary)
                        }
                    }
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

                    if !operations.isEmpty {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.secondary)
                    }
                }
            }

            if isExpanded && !operations.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(operations) { op in
                        HStack(spacing: 8) {
                            Text(op.itemPath)
                                .font(.caption)
                                .foregroundColor(.primary)
                                .lineLimit(1)
                                .truncationMode(.middle)

                            Spacer(minLength: 8)

                            if let mode = op.deletionMode {
                                Text(mode == OperationRecord.DeletionMode.permanent.rawValue ? "history_mode_permanent".localized : "history_mode_trash".localized)
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }

                            if let failed = op.failed, failed > 0 {
                                Text("history_ops_failed_format".localizedWithArgs(Int64(failed)))
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                            } else if let skipped = op.skipped, skipped > 0 {
                                Text("history_ops_skipped_format".localizedWithArgs(Int64(skipped)))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }

                            Text(op.bytesFreed.formattedByteCount())
                                .font(.caption.monospacedDigit())
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.leading, 44)
                .padding(.top, 2)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .onTapGesture {
            guard !operations.isEmpty else { return }
            withAnimation(.easeInOut(duration: 0.15)) {
                isExpanded.toggle()
            }
        }
    }
}

#Preview {
    CleanupHistoryView()
}

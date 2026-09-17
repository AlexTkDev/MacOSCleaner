import SwiftUI
import Charts

struct DashboardView: View {
    @Environment(\.openWindow) private var openWindow
    @StateObject private var viewModel: DashboardViewModel
    @State private var showHistorySheet = false
    private let journal: TransactionJournal
    private let onNavigateToCleanup: (() -> Void)?
    
    init(journal: TransactionJournal, onNavigateToCleanup: (() -> Void)? = nil) {
        self.journal = journal
        self.onNavigateToCleanup = onNavigateToCleanup
        _viewModel = StateObject(wrappedValue: DashboardViewModel(journal: journal))
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 16) {
                    diskUsageCard
                    rightColumn
                }
                .fixedSize(horizontal: false, vertical: true)
                
                recentOperationsSection
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
            .padding(.top, 8)
        }
        .sheet(isPresented: $showHistorySheet) {
            CleanupHistoryView(journal: journal)
        }
        .task {
            await viewModel.refresh()
        }
    }
    
    // Right column: Stats + System Info stacked
    private var rightColumn: some View {
        VStack(alignment: .leading, spacing: 12) {
            statsCard
            systemInfoCard
        }
        .frame(width: 240)
    }
    
    private var diskCardHeader: some View {
        HStack(alignment: .center) {
            HStack(spacing: 8) {
                Image(systemName: "internaldrive.fill")
                    .font(.title3)
                    .foregroundColor(.accentColor)
                
                Text("dashboard_disk_usage".localized)
                    .font(.headline)
            }
            
            Spacer()
            
            HStack(spacing: 12) {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("dashboard_free".localized)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(viewModel.freeDiskSpace.formattedByteCount())
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                }
                
                Divider()
                    .frame(height: 20)
                
                VStack(alignment: .trailing, spacing: 2) {
                    Text("dashboard_total".localized)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(viewModel.totalDiskSpace.formattedByteCount())
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.primary.opacity(0.04))
            )
        }
    }
    
    private var diskUsageCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            diskCardHeader
            
            if viewModel.isCategoriesLoading {
                VStack(spacing: 12) {
                    Spacer(minLength: 0)
                    LiquidGlassLoaderView(size: 36)
                    Text("disk_analyzer_scanning".localized)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                DiskRingsChartView(
                    items: viewModel.diskCategories,
                    totalUsed: viewModel.usedDiskSpace,
                    totalDisk: viewModel.totalDiskSpace
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassCard()
    }
    
    private var statsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("dashboard_statistics".localized, systemImage: "chart.bar")
                .font(.headline)
            
            VStack(spacing: 8) {
                StatRow(title: "dashboard_total_freed".localized, value: viewModel.totalFreedBytes.formattedByteCount(), icon: "trash")
                StatRow(title: "dashboard_cleanups".localized, value: "\(viewModel.cleanupCount)", icon: "arrow.counterclockwise")
                StatRow(title: "dashboard_status".localized, value: "dashboard_healthy".localized, icon: "checkmark.circle", color: .green)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }
    
    private var systemInfoCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("dashboard_system_info".localized, systemImage: "info.circle")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 6) {
                SystemInfoItem(title: "dashboard_model".localized, value: viewModel.systemInfo.model, icon: "laptopcomputer")
                SystemInfoItem(title: "dashboard_os_version".localized, value: viewModel.systemInfo.osVersion, icon: "info.circle")
                SystemInfoItem(title: "dashboard_processor".localized, value: viewModel.systemInfo.processor, icon: "cpu")
                SystemInfoItem(title: "dashboard_memory".localized, value: viewModel.systemInfo.memory, icon: "memorychip")
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }
    
    private var recentOperationsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("dashboard_recent_operations".localized, systemImage: "clock")
                .font(.headline)
            
            if viewModel.recentRecords.isEmpty {
                Button {
                    onNavigateToCleanup?()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 15))
                            .foregroundColor(.accentColor)
                        
                        Text("dashboard_history_empty_hint".localized)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        
                        Spacer()
                        
                        HStack(spacing: 4) {
                            Text("dashboard_start_cleanup".localized)
                                .font(.system(size: 12, weight: .semibold))
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .bold))
                        }
                        .foregroundColor(.accentColor)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
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
                .buttonStyle(.plain)
                .onHover { inside in
                    if inside {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }
            } else {
                HStack(spacing: 12) {
                    ForEach(viewModel.recentRecords) { record in
                        CleanupCardView(record: record)
                    }
                }
                
                Button {
                    openWindow(id: "cleanup-history")
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 12))
                        Text("dashboard_view_all_history".localized)
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundColor(.accentColor)
                }
                .buttonStyle(.plain)
                .onHover { inside in
                    if inside {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 2)
            }
        }
    }
}

struct StatRow: View {
    let title: String
    let value: String
    let icon: String
    var color: Color = .accentColor
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(color)
                .frame(width: 32)
            
            VStack(alignment: .leading) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.headline)
            }
            Spacer()
        }
    }
}

struct TransactionRow: View {
    let transaction: CleanupTransaction
    
    var totalFreed: Int64 {
        transaction.operations.reduce(0) { $0 + $1.bytesFreed }
    }
    
    var body: some View {
        HStack {
            VStack(alignment: .leading) {
                Text(transaction.timestamp.formatted(.dateTime.year().month().day().locale(LanguageManager.shared.currentLocale)))
                    .fontWeight(.medium)
                Text(transaction.timestamp.formatted(.dateTime.hour().minute().locale(LanguageManager.shared.currentLocale)))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text(String(format: "dashboard_freed_prefix".localized, totalFreed.formattedByteCount()))
                .foregroundColor(.green)
                .fontWeight(.bold)
        }
        .padding()
    }
}

struct DiskStatItem: View {
    let title: String
    let value: Int64
    let color: Color?
    var alignment: HorizontalAlignment = .leading
    
    var body: some View {
        VStack(alignment: alignment) {
            HStack(spacing: 4) {
                if let color = color {
                    Circle()
                        .fill(color)
                        .frame(width: 8, height: 8)
                }
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Text(value.formattedByteCount())
                .fontWeight(.medium)
        }
    }
}

struct SystemInfoItem: View {
    let title: String
    let value: String
    let icon: String
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.accentColor)
                .frame(width: 32)
            
            VStack(alignment: .leading) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
        }
    }
}

#Preview {
    DashboardView(journal: TransactionJournal())
}

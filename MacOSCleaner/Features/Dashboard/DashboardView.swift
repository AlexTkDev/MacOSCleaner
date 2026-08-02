import SwiftUI
import Charts

struct DashboardView: View {
    @StateObject private var viewModel: DashboardViewModel
    
    init(journal: TransactionJournal) {
        _viewModel = StateObject(wrappedValue: DashboardViewModel(journal: journal))
    }
    
    var body: some View {
        GlassEffectContainer {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(spacing: 20) {
                        diskUsageCard
                        rightColumn
                    }
                    
                    recentOperationsSection
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
                .padding(.top, 8)
            }
        }
        .task {
            await viewModel.refresh()
        }
    }
    
    // Right column: Stats + System Info stacked (Compact width to give diskUsageCard maximum space)
    private var rightColumn: some View {
        VStack(alignment: .leading, spacing: 16) {
            statsCard
            systemInfoCard
        }
        .frame(width: 260)
    }
    
    private var systemInfoCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("dashboard_system_info".localized, systemImage: "info.circle")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 10) {
                SystemInfoItem(title: "dashboard_model".localized, value: viewModel.systemInfo.model, icon: "laptopcomputer")
                SystemInfoItem(title: "dashboard_os_version".localized, value: viewModel.systemInfo.osVersion, icon: "info.circle")
                SystemInfoItem(title: "dashboard_processor".localized, value: viewModel.systemInfo.processor, icon: "cpu")
                SystemInfoItem(title: "dashboard_memory".localized, value: viewModel.systemInfo.memory, icon: "memorychip")
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }
    
    private var diskUsageCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            if viewModel.isCategoriesLoading {
                VStack(spacing: 12) {
                    LiquidGlassLoaderView(size: 48)
                    Text("disk_analyzer_scanning".localized)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                DiskRingsChartView(
                    items: viewModel.diskCategories,
                    totalUsed: viewModel.usedDiskSpace,
                    totalDisk: viewModel.totalDiskSpace
                )
                .frame(maxHeight: .infinity)
            }
        }
        .padding()
        .frame(maxHeight: .infinity)
        .glassCard()
    }
    
    private var statsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("dashboard_statistics".localized, systemImage: "chart.bar")
                .font(.headline)
            
            VStack(spacing: 12) {
                StatRow(title: "dashboard_total_freed".localized, value: viewModel.totalFreedBytes.formattedByteCount(), icon: "trash")
                StatRow(title: "dashboard_cleanups".localized, value: "\(viewModel.cleanupCount)", icon: "arrow.counterclockwise")
                StatRow(title: "dashboard_status".localized, value: "dashboard_healthy".localized, icon: "checkmark.circle", color: .green)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassCard()
    }
    
    private var recentOperationsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("dashboard_recent_operations".localized, systemImage: "clock")
                .font(.headline)
            
            if viewModel.recentTransactions.isEmpty {
                Text("dashboard_no_recent_operations".localized)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 40)
                    .glassCard()
            } else {
                VStack(spacing: 0) {
                    ForEach(viewModel.recentTransactions) { transaction in
                        TransactionRow(transaction: transaction)
                        if transaction.id != viewModel.recentTransactions.last?.id {
                            Divider()
                        }
                    }
                }
                .glassCard()
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

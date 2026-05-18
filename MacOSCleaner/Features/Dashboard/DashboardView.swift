import SwiftUI
import Charts

struct DashboardView: View {
    @StateObject private var viewModel: DashboardViewModel
    
    init(journal: TransactionJournal) {
        _viewModel = StateObject(wrappedValue: DashboardViewModel(journal: journal))
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Dashboard")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                
                HStack(alignment: .top, spacing: 20) {
                    diskUsageCard
                    statsCard
                }
                
                systemInfoSection
                
                recentOperationsSection
            }
            .padding(24)
        }
        .task {
            await viewModel.refresh()
        }
    }
    
    private var systemInfoSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("System Information")
                .font(.headline)
            
            HStack(spacing: 40) {
                SystemInfoItem(title: "Model", value: viewModel.systemInfo.model, icon: "laptopcomputer")
                SystemInfoItem(title: "OS Version", value: viewModel.systemInfo.osVersion, icon: "info.circle")
                SystemInfoItem(title: "Processor", value: viewModel.systemInfo.processor, icon: "cpu")
                SystemInfoItem(title: "Memory", value: viewModel.systemInfo.memory, icon: "memorychip")
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(NSColor.windowBackgroundColor))
            .cornerRadius(12)
        }
    }
    
    private var diskUsageCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Disk Usage")
                .font(.headline)
            
            ZStack {
                Chart {
                    SectorMark(
                        angle: .value("Used", viewModel.usedDiskSpace),
                        innerRadius: .ratio(0.55),
                        angularInset: 2
                    )
                    .foregroundStyle(Color.accentColor)
                    
                    SectorMark(
                        angle: .value("Free", viewModel.freeDiskSpace),
                        innerRadius: .ratio(0.55),
                        angularInset: 2
                    )
                    .foregroundStyle(Color.secondary.opacity(0.15))
                }
                .frame(height: 200)
                
                VStack {
                    Text("\(Int(viewModel.usedDiskPercentage * 100))%")
                        .font(.system(size: 28, weight: .bold))
                        .minimumScaleFactor(0.5)
                    Text("Used")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            HStack(spacing: 0) {
                DiskStatItem(title: "Used", value: viewModel.usedDiskSpace, color: .accentColor)
                Spacer()
                DiskStatItem(title: "Free", value: viewModel.freeDiskSpace, color: .secondary.opacity(0.4))
                Spacer()
                DiskStatItem(title: "Total", value: viewModel.totalDiskSpace, color: nil, alignment: .trailing)
            }
        }
        .padding()
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(12)
        .frame(maxWidth: .infinity)
    }
    
    private var statsCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Statistics")
                .font(.headline)
            
            VStack(spacing: 20) {
                StatRow(title: "Total Freed", value: ByteCountFormatter.string(fromByteCount: viewModel.totalFreedBytes, countStyle: .file), icon: "trash")
                StatRow(title: "Cleanups", value: "\(viewModel.cleanupCount)", icon: "arrow.counterclockwise")
                StatRow(title: "Status", value: "Healthy", icon: "checkmark.circle", color: .green)
            }
            Spacer()
        }
        .padding()
        .background(Color(NSColor.windowBackgroundColor))
        .cornerRadius(12)
        .frame(maxWidth: .infinity)
    }
    
    private var recentOperationsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Recent Operations")
                .font(.headline)
            
            if viewModel.recentTransactions.isEmpty {
                Text("No recent operations")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 40)
            } else {
                VStack(spacing: 0) {
                    ForEach(viewModel.recentTransactions) { transaction in
                        TransactionRow(transaction: transaction)
                        if transaction.id != viewModel.recentTransactions.last?.id {
                            Divider()
                        }
                    }
                }
                .background(Color(NSColor.windowBackgroundColor))
                .cornerRadius(12)
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
                Text(transaction.timestamp, style: .date)
                    .fontWeight(.medium)
                Text(transaction.timestamp, style: .time)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Text("+\(ByteCountFormatter.string(fromByteCount: totalFreed, countStyle: .file))")
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
            Text(ByteCountFormatter.string(fromByteCount: value, countStyle: .file))
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

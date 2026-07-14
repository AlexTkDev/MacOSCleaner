import SwiftUI
import Charts

// MARK: - Model

public struct DiskCategoryItem: Identifiable, Sendable, Hashable {
    public let id = UUID()
    public let label: String
    public let bytes: Int64
    public let color: Color
    public let isFree: Bool
    
    public var formattedValue: String { bytes.formattedByteCount() }
    
    public init(label: String, bytes: Int64, color: Color, isFree: Bool = false) {
        self.label = label
        self.bytes = bytes
        self.color = color
        self.isFree = isFree
    }
}

// MARK: - Donut Chart View

public struct DiskDonutChartView: View {
    let items: [DiskCategoryItem]
    let totalUsed: Int64
    let totalDisk: Int64
    
    @State private var hoveredID: UUID? = nil
    
    public init(items: [DiskCategoryItem], totalUsed: Int64, totalDisk: Int64) {
        self.items = items
        self.totalUsed = totalUsed
        self.totalDisk = totalDisk
    }
    
    private var hoveredItem: DiskCategoryItem? {
        guard let id = hoveredID else { return nil }
        return items.first { $0.id == id }
    }
    
    private var usedPercent: Int {
        guard totalDisk > 0 else { return 0 }
        return Int((Double(totalUsed) / Double(totalDisk)) * 100)
    }
    
    public var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Chart(items) { item in
                    SectorMark(
                        angle: .value(item.label, item.bytes),
                        innerRadius: .ratio(0.55),
                        angularInset: hoveredID == item.id ? 3 : 1.5
                    )
                    .foregroundStyle(item.color)
                    .opacity(hoveredID == nil || hoveredID == item.id ? 1.0 : 0.45)
                }
                .frame(height: 220)
                
                // Center label
                VStack(spacing: 2) {
                    if let h = hoveredItem {
                        Text(h.label)
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                        Text(h.formattedValue)
                            .font(.system(size: 20, weight: .bold))
                            .minimumScaleFactor(0.6)
                    } else {
                        Text("\(usedPercent)%")
                            .font(.system(size: 28, weight: .bold))
                            .minimumScaleFactor(0.5)
                        Text("dashboard_used".localized)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .animation(.easeInOut(duration: 0.2), value: hoveredID)
                .frame(width: 100)
            }
            // Hit testing overlay per sector is not directly supported in Charts,
            // so we use the legend rows as hover targets
            legendView
        }
    }
    
    private var legendView: some View {
        let usedItems = items.filter { !$0.isFree }
        let freeItem = items.first { $0.isFree }
        let columns = [GridItem(.flexible()), GridItem(.flexible())]
        return VStack(alignment: .leading, spacing: 4) {
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(usedItems) { item in
                    legendRow(item: item)
                }
            }
            if let free = freeItem {
                Divider().padding(.vertical, 2)
                legendRow(item: free)
            }
        }
    }
    
    private func legendRow(item: DiskCategoryItem) -> some View {
        HStack(spacing: 6) {
            if item.isFree {
                RoundedRectangle(cornerRadius: 3)
                    .stroke(Color.secondary, lineWidth: 1.5)
                    .frame(width: 10, height: 10)
            } else {
                RoundedRectangle(cornerRadius: 3)
                    .fill(item.color)
                    .frame(width: 10, height: 10)
            }
            Text(item.label)
                .font(.caption)
                .foregroundColor(item.isFree ? .secondary : .primary)
                .lineLimit(1)
            Spacer(minLength: 0)
            Text(item.formattedValue)
                .font(.caption2)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .background(
            !item.isFree && hoveredID == item.id
                ? item.color.opacity(0.15)
                : Color.clear
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .contentShape(Rectangle())
        .onHover { isHovered in
            guard !item.isFree else { return }
            withAnimation(.easeInOut(duration: 0.15)) {
                hoveredID = isHovered ? item.id : nil
            }
        }
    }
}

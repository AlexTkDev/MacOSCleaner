import SwiftUI

// MARK: - Disk Rings Chart View (Apple Watch Activity Rings Style)

public struct DiskRingsChartView: View {
    let items: [DiskCategoryItem]
    let totalUsed: Int64
    let totalDisk: Int64
    
    @State private var hoveredID: UUID? = nil
    
    public init(items: [DiskCategoryItem], totalUsed: Int64, totalDisk: Int64) {
        self.items = items
        self.totalUsed = totalUsed
        self.totalDisk = totalDisk
    }
    
    private var usedCategoryItems: [DiskCategoryItem] {
        items.filter { !$0.isFree && $0.bytes > 0 }
    }
    
    private var sortedItems: [DiskCategoryItem] {
        usedCategoryItems.sorted { $0.bytes > $1.bytes }
    }
    
    private var freeDisk: Int64 {
        max(0, totalDisk - totalUsed)
    }
    
    private var usedPercent: Int {
        guard totalDisk > 0 else { return 0 }
        return Int((Double(totalUsed) / Double(totalDisk)) * 100)
    }
    
    private func formattedCategoryPercent(for bytes: Int64) -> String {
        guard totalUsed > 0, bytes > 0 else { return "0%" }
        let raw = (Double(bytes) / Double(totalUsed)) * 100.0
        let rounded = Int(round(raw))
        if rounded == 0 {
            return "<1%"
        } else {
            return "\(rounded)%"
        }
    }
    
    private var hoveredItem: DiskCategoryItem? {
        sortedItems.first { $0.id == hoveredID }
    }
    
    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            cardHeader
            
            Spacer(minLength: 0)
            
            HStack(alignment: .center, spacing: 24) {
                legendGrid
                    .frame(width: 250)
                
                Spacer()
                
                ringsChart
                    .frame(width: 270, height: 270)
                
                Spacer()
            }
            
            Spacer(minLength: 0)
        }
        .frame(maxHeight: .infinity)
    }
    
    // MARK: - Card Header
    
    private var cardHeader: some View {
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
                    Text(freeDisk.formattedByteCount())
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
                    Text(totalDisk.formattedByteCount())
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
    
    // MARK: - Rings Chart
    
    private var ringsChart: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let centerHoleRadius: CGFloat = 28
            let availableRadius = (size / 2) - centerHoleRadius
            let ringCount = CGFloat(max(1, sortedItems.count))
            let spacing: CGFloat = 3.0
            let ringWidth = max(10, min(30, (availableRadius - spacing * ringCount) / ringCount))
            
            ZStack {
                // Center Interactive Text
                VStack(spacing: 1) {
                    if let hovered = hoveredItem {
                        let pctString = formattedCategoryPercent(for: hovered.bytes)
                        Text(pctString)
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundColor(hovered.color)
                            .transition(.opacity)
                        Text(hovered.label)
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(maxWidth: centerHoleRadius * 1.7)
                            .transition(.opacity)
                    } else {
                        Text("\(usedPercent)%")
                            .font(.system(size: 22, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)
                            .transition(.opacity)
                        Text("dashboard_used".localized)
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                            .frame(maxWidth: centerHoleRadius * 1.7)
                            .transition(.opacity)
                    }
                }
                .animation(.easeInOut(duration: 0.15), value: hoveredID)
                
                // Concentric Activity Rings
                ForEach(Array(sortedItems.enumerated()), id: \.element.id) { index, item in
                    let radius = (size / 2) - CGFloat(index) * (ringWidth + spacing) - ringWidth / 2
                    let progress = totalUsed > 0 ? max(0.015, Double(item.bytes) / Double(totalUsed)) : 0.0
                    let isHovered = hoveredID == item.id
                    let isDimmed = hoveredID != nil && !isHovered
                    
                    ZStack {
                        // Background Track
                        Circle()
                            .stroke(item.color.opacity(0.12), lineWidth: ringWidth)
                        
                        // Progress Arc
                        Circle()
                            .trim(from: 0, to: CGFloat(progress))
                            .stroke(
                                LinearGradient(colors: item.gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing),
                                style: StrokeStyle(lineWidth: ringWidth, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                            .shadow(color: isHovered ? item.color.opacity(0.65) : item.color.opacity(0.15), radius: isHovered ? 5 : 1, x: 0, y: 1)
                    }
                    .frame(width: max(10, radius * 2), height: max(10, radius * 2))
                    .opacity(isDimmed ? 0.35 : 1.0)
                    .scaleEffect(isHovered ? 1.03 : 1.0)
                    .animation(.spring(response: 0.25, dampingFraction: 0.7), value: isHovered)
                    .contentShape(Circle().stroke(lineWidth: ringWidth + 4))
                    .onHover { hover in
                        withAnimation(.easeInOut(duration: 0.15)) {
                            hoveredID = hover ? item.id : nil
                        }
                    }
                }
            }
            .frame(width: size, height: size)
            .position(x: geo.size.width / 2, y: geo.size.height / 2)
        }
    }
    
    // MARK: - Legend Grid (Single Column Left Layout)
    
    private var legendGrid: some View {
        VStack(spacing: 6) {
            ForEach(sortedItems) { item in
                legendCard(item: item)
            }
        }
    }
    
    private func legendCard(item: DiskCategoryItem) -> some View {
        let isHovered = hoveredID == item.id
        let isDimmed = hoveredID != nil && !isHovered
        let pctString = formattedCategoryPercent(for: item.bytes)
        
        return HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 6)
                .fill(LinearGradient(colors: item.gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 24, height: 24)
                .overlay(
                    Image(systemName: item.iconName)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white)
                )
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(item.label)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    
                    Spacer(minLength: 0)
                    
                    Text(pctString)
                        .font(.subheadline)
                        .fontWeight(.bold)
                        .foregroundColor(isHovered ? item.color : .primary)
                }
                
                Text(item.formattedValue)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .opacity(isDimmed ? 0.4 : 1.0)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isHovered ? item.color.opacity(0.18) : Color.primary.opacity(0.04))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isHovered ? item.color.opacity(0.5) : Color.clear, lineWidth: 1)
        )
        .contentShape(Rectangle())
        .onHover { isHover in
            withAnimation(.easeInOut(duration: 0.15)) {
                hoveredID = isHover ? item.id : nil
            }
        }
    }
}

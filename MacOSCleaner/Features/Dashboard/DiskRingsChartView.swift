import SwiftUI

// MARK: - Disk Rings Chart View (Apple Watch Activity Rings Style)

public struct DiskRingsChartView: View {
    let items: [DiskCategoryItem]
    let totalUsed: Int64
    let totalDisk: Int64
    let isScanning: Bool
    let completedCategories: Int
    let totalCategories: Int

    @State private var hoveredID: String? = nil
    @State private var selectedID: String? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(
        items: [DiskCategoryItem],
        totalUsed: Int64,
        totalDisk: Int64,
        isScanning: Bool = false,
        completedCategories: Int = 0,
        totalCategories: Int = 0
    ) {
        self.items = items
        self.totalUsed = totalUsed
        self.totalDisk = totalDisk
        self.isScanning = isScanning
        self.completedCategories = completedCategories
        self.totalCategories = totalCategories
    }

    private var displayItems: [DiskCategoryItem] {
        // Keep category order fixed while scanning so live size updates do not reorder rows.
        if isScanning {
            return items
        }
        return items.filter { $0.bytes > 0 }.sorted { $0.bytes > $1.bytes }
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

    private var activeID: String? {
        hoveredID ?? selectedID
    }

    private var hoveredItem: DiskCategoryItem? {
        displayItems.first { $0.id == activeID }
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
        HStack(alignment: .center, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "internaldrive.fill")
                    .font(.title3)
                    .foregroundColor(.accentColor)

                Text("dashboard_disk_usage".localized)
                    .font(.headline)

                if isScanning {
                    scanningBadge
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.2), value: isScanning)

            Spacer()

            HStack(spacing: 12) {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("dashboard_free".localized)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(totalDisk > 0 ? freeDisk.formattedByteCount() : "—")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                        .foregroundColor(.primary)
                }

                Divider()
                    .frame(height: 20)

                VStack(alignment: .trailing, spacing: 2) {
                    Text("dashboard_total".localized)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(totalDisk > 0 ? totalDisk.formattedByteCount() : "—")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                        .foregroundColor(.primary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
            )
        }
    }

    private var scanningBadge: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isScanning || reduceMotion)) { timeline in
            let pulse = reduceMotion
                ? 0.9
                : 0.45 + 0.55 * (0.5 + 0.5 * sin(timeline.date.timeIntervalSince1970 * 4.0))

            HStack(spacing: 6) {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 6, height: 6)
                    .opacity(pulse)

                Text("disk_analyzer_scanning".localized)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(.accentColor)

                if totalCategories > 0 {
                    Text("\(completedCategories)/\(totalCategories)")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .monospacedDigit()
                        .foregroundColor(.accentColor.opacity(0.85))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(Color.accentColor.opacity(0.12))
            )
            .overlay(
                Capsule()
                    .strokeBorder(Color.accentColor.opacity(0.25), lineWidth: 1)
            )
        }
    }

    // MARK: - Rings Chart

    private var ringsChart: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let centerHoleRadius: CGFloat = 31
            let availableRadius = (size / 2) - centerHoleRadius
            let ringCount = CGFloat(max(1, displayItems.count))
            let spacing: CGFloat = 3.0
            let ringWidth = max(10, min(30, (availableRadius - spacing * ringCount) / ringCount))

            TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isScanning || reduceMotion)) { timeline in
                let elapsed = timeline.date.timeIntervalSince1970

                ZStack {
                    ringCenterContent(centerHoleRadius: centerHoleRadius)

                    ForEach(Array(displayItems.enumerated()), id: \.element.id) { index, item in
                        let radius = (size / 2) - CGFloat(index) * (ringWidth + spacing) - ringWidth / 2
                        ringRow(
                            index: index,
                            item: item,
                            radius: radius,
                            ringWidth: ringWidth,
                            elapsed: elapsed
                        )
                    }
                }
                .frame(width: size, height: size)
                .position(x: geo.size.width / 2, y: geo.size.height / 2)
            }
        }
    }

    @ViewBuilder
    private func ringCenterContent(centerHoleRadius: CGFloat) -> some View {
        ZStack {
            if isScanning && totalCategories > 0 && hoveredItem == nil {
                let scanFraction = CGFloat(completedCategories) / CGFloat(totalCategories)
                let innerDiameter = max(20, (centerHoleRadius * 2) - 4)
                Circle()
                    .stroke(Color.accentColor.opacity(0.16), lineWidth: 2.5)
                    .frame(width: innerDiameter, height: innerDiameter)
                Circle()
                    .trim(from: 0, to: max(0.04, scanFraction))
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .frame(width: innerDiameter, height: innerDiameter)
                    .rotationEffect(.degrees(-90))
                    .animation(.spring(response: 0.35, dampingFraction: 0.8), value: scanFraction)
            }

            VStack(spacing: 1) {
                if let hovered = hoveredItem {
                    let valueText = hovered.isScanning && hovered.bytes == 0
                        ? "..."
                        : formattedCategoryPercent(for: hovered.bytes)
                    Text(valueText)
                        .font(.system(size: 21, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(hovered.color)
                        .transition(.opacity)
                    Text(hovered.label)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: centerHoleRadius * 1.6)
                        .transition(.opacity)
                } else {
                    Text("\(usedPercent)%")
                        .font(.system(size: 21, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundColor(.primary)
                        .transition(.opacity)
                    Text("dashboard_used".localized)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(.secondary.opacity(0.9))
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: centerHoleRadius * 1.6)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.15), value: activeID)
        }
    }

    private func ringRow(
        index: Int,
        item: DiskCategoryItem,
        radius: CGFloat,
        ringWidth: CGFloat,
        elapsed: TimeInterval
    ) -> some View {
        let progress = totalUsed > 0 ? max(0.015, Double(item.bytes) / Double(totalUsed)) : 0.0
        let isHovered = activeID == item.id
        let isDimmed = activeID != nil && !isHovered

        return ZStack {
            Circle()
                .stroke(item.color.opacity(item.isScanning ? 0.16 : 0.12), lineWidth: ringWidth)

            if item.isScanning {
                if item.bytes > 0 && totalUsed > 0 {
                    let liveProgress = min(1.0, max(0.02, Double(item.bytes) / Double(totalUsed)))
                    Circle()
                        .trim(from: 0, to: CGFloat(liveProgress))
                        .stroke(
                            LinearGradient(colors: item.gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing),
                            style: StrokeStyle(lineWidth: ringWidth, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))
                        .opacity(0.65)
                        .animation(.easeOut(duration: 0.25), value: liveProgress)
                }

                if !reduceMotion {
                    scanningRingSweep(index: index, item: item, ringWidth: ringWidth, elapsed: elapsed)
                }
            } else {
                Circle()
                    .trim(from: 0, to: CGFloat(progress))
                    .stroke(
                        LinearGradient(colors: item.gradientColors, startPoint: .topLeading, endPoint: .bottomTrailing),
                        style: StrokeStyle(lineWidth: ringWidth, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .shadow(color: isHovered ? item.color.opacity(0.65) : item.color.opacity(0.15), radius: isHovered ? 5 : 1, x: 0, y: 1)
                    .animation(.spring(response: 0.5, dampingFraction: 0.82), value: progress)
            }
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
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedID = (selectedID == item.id) ? nil : item.id
            }
        }
    }

    private func scanningRingSweep(
        index: Int,
        item: DiskCategoryItem,
        ringWidth: CGFloat,
        elapsed: TimeInterval
    ) -> some View {
        let sweepAngle = (elapsed * (95 + Double(index) * 18) + Double(index) * 55).truncatingRemainder(dividingBy: 360)
        return Circle()
            .trim(from: 0, to: 0.18)
            .stroke(
                AngularGradient(
                    gradient: Gradient(colors: [
                        item.color.opacity(0.0),
                        (item.gradientColors.first ?? item.color).opacity(0.45),
                        item.gradientColors.last ?? item.color
                    ]),
                    center: .center,
                    startAngle: .degrees(0),
                    endAngle: .degrees(65)
                ),
                style: StrokeStyle(lineWidth: ringWidth, lineCap: .round)
            )
            .rotationEffect(.degrees(sweepAngle))
    }

    // MARK: - Legend Grid (Single Column Left Layout)

    private var legendGrid: some View {
        VStack(spacing: 6) {
            ForEach(displayItems) { item in
                legendCard(item: item)
            }
        }
    }

    private func legendCard(item: DiskCategoryItem) -> some View {
        let isHovered = activeID == item.id
        let isDimmed = activeID != nil && !isHovered
        let pctString = formattedCategoryPercent(for: item.bytes)

        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 8) {
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

                        if item.isScanning {
                            if reduceMotion {
                                Circle()
                                    .fill(item.color.opacity(0.75))
                                    .frame(width: 7, height: 7)
                            } else {
                                ProgressView()
                                    .controlSize(.mini)
                                    .scaleEffect(0.65)
                                    .frame(width: 14, height: 14)
                            }
                        } else {
                            Text(pctString)
                                .font(.subheadline)
                                .fontWeight(.bold)
                                .monospacedDigit()
                                .foregroundColor(isHovered ? item.color : .primary)
                        }
                    }

                    if item.isScanning && item.bytes == 0 {
                        Text("disk_analyzer_scanning".localized)
                            .font(.caption)
                            .foregroundColor(.secondary.opacity(0.75))
                            .lineLimit(1)
                    } else {
                        Text(item.formattedValue)
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundColor(.secondary.opacity(0.95))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
            }

            if item.isScanning {
                scanningBar(color: item.color)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .opacity(isDimmed ? 0.4 : 1.0)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isHovered ? item.color.opacity(0.22) : Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isHovered ? item.color.opacity(0.65) : Color.white.opacity(0.09), lineWidth: 1)
        )
        .animation(.easeInOut(duration: 0.2), value: item.isScanning)
        .contentShape(Rectangle())
        .onHover { isHover in
            withAnimation(.easeInOut(duration: 0.15)) {
                hoveredID = isHover ? item.id : nil
            }
        }
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedID = (selectedID == item.id) ? nil : item.id
            }
        }
    }

    private func scanningBar(color: Color) -> some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !isScanning || reduceMotion)) { timeline in
            GeometryReader { geo in
                let width = max(1, geo.size.width)
                let barWidth = width * 0.42
                let phase = reduceMotion
                    ? 0.3
                    : (timeline.date.timeIntervalSince1970 * 0.75).truncatingRemainder(dividingBy: 1.0)
                let offsetX = (width + barWidth) * CGFloat(phase) - barWidth

                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(color.opacity(0.15))
                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [color.opacity(0.15), color.opacity(0.85), color.opacity(0.15)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: reduceMotion ? width * 0.35 : barWidth)
                        .offset(x: reduceMotion ? 0 : offsetX)
                }
                .clipShape(Capsule())
            }
            .frame(height: 2)
        }
    }
}

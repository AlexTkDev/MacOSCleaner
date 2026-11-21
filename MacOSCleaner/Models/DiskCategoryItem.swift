import SwiftUI

public struct DiskCategoryItem: Identifiable, Sendable, Hashable {
    public let id: String
    public let label: String
    public let bytes: Int64
    public let color: Color
    public let gradientColors: [Color]
    public let iconName: String
    public let isScanning: Bool

    public init(
        id: String = UUID().uuidString,
        label: String,
        bytes: Int64,
        color: Color,
        gradientColors: [Color] = [],
        iconName: String = "circle.fill",
        isScanning: Bool = false
    ) {
        self.id = id
        self.label = label
        self.bytes = bytes
        self.color = color
        self.gradientColors = gradientColors.isEmpty ? [color.opacity(0.8), color] : gradientColors
        self.iconName = iconName
        self.isScanning = isScanning
    }

    public var formattedValue: String {
        bytes.formattedByteCount()
    }
}

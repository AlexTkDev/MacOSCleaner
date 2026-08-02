import SwiftUI

public struct DiskCategoryItem: Identifiable, Sendable, Hashable {
    public let id = UUID()
    public let label: String
    public let bytes: Int64
    public let color: Color
    public let gradientColors: [Color]
    public let iconName: String
    public let isFree: Bool
    
    public init(
        label: String,
        bytes: Int64,
        color: Color,
        gradientColors: [Color] = [],
        iconName: String = "circle.fill",
        isFree: Bool = false
    ) {
        self.label = label
        self.bytes = bytes
        self.color = color
        self.gradientColors = gradientColors.isEmpty ? [color.opacity(0.8), color] : gradientColors
        self.iconName = iconName
        self.isFree = isFree
    }
    
    public var formattedValue: String {
        return bytes.formattedByteCount()
    }
}

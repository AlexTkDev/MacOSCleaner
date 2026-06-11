import Foundation

public struct CleanupPreviewItem: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let label: String
    public var sizeMB: Int
    public let risk: OperationRisk
    public var isSelected: Bool
    public let isDeletable: Bool
    public let description: String?
    public var children: [CleanupPreviewItem]
    
    public init(id: UUID = UUID(), label: String, sizeMB: Int, risk: OperationRisk, isSelected: Bool = true, isDeletable: Bool, description: String? = nil, children: [CleanupPreviewItem] = []) {
        self.id = id
        self.label = label
        self.sizeMB = sizeMB
        self.risk = risk
        self.isSelected = isSelected
        self.isDeletable = isDeletable
        self.description = description
        self.children = children
    }
    
    public static func == (lhs: CleanupPreviewItem, rhs: CleanupPreviewItem) -> Bool {
        lhs.id == rhs.id &&
        lhs.sizeMB == rhs.sizeMB &&
        lhs.isSelected == rhs.isSelected &&
        lhs.children == rhs.children &&
        lhs.description == rhs.description
    }
}

public struct CleanupResultItem: Identifiable, Sendable {
    public let id: UUID = UUID()
    public let label: String
    public let freedMB: Int
}

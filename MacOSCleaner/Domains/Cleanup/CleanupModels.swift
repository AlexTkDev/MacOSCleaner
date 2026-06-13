import Foundation

public struct CleanupFileItem: Sendable {
    public let path: String
    public let sizeBytes: Int64
    public let modificationDate: Date?
    public let isDirectory: Bool

    public init(path: String, sizeBytes: Int64, modificationDate: Date?, isDirectory: Bool) {
        self.path = path
        self.sizeBytes = sizeBytes
        self.modificationDate = modificationDate
        self.isDirectory = isDirectory
    }
}

public struct CleanupPreviewItem: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let label: String
    public var sizeMB: Int
    public let risk: OperationRisk
    public var isSelected: Bool
    public let isDeletable: Bool
    public let description: String?
    public var children: [CleanupPreviewItem]
    public var path: String?
    public var modificationDate: Date?
    public var category: String?

    public init(
        id: UUID = UUID(),
        label: String,
        sizeMB: Int,
        risk: OperationRisk,
        isSelected: Bool = true,
        isDeletable: Bool,
        description: String? = nil,
        children: [CleanupPreviewItem] = [],
        path: String? = nil,
        modificationDate: Date? = nil,
        category: String? = nil
    ) {
        self.id = id
        self.label = label
        self.sizeMB = sizeMB
        self.risk = risk
        self.isSelected = isSelected
        self.isDeletable = isDeletable
        self.description = description
        self.children = children
        self.path = path
        self.modificationDate = modificationDate
        self.category = category
    }

    public static func == (lhs: CleanupPreviewItem, rhs: CleanupPreviewItem) -> Bool {
        lhs.id == rhs.id &&
        lhs.sizeMB == rhs.sizeMB &&
        lhs.isSelected == rhs.isSelected &&
        lhs.children == rhs.children &&
        lhs.description == rhs.description &&
        lhs.path == rhs.path
    }
}

public struct CleanupResultItem: Identifiable, Sendable {
    public let id: UUID = UUID()
    public let label: String
    public let freedMB: Int
}

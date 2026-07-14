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
    public var sizeBytes: Int64
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
        sizeBytes: Int64 = 0,
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
        self.sizeBytes = sizeBytes == 0 ? Int64(sizeMB) * 1024 * 1024 : sizeBytes
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
        lhs.sizeBytes == rhs.sizeBytes &&
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
    public let freedBytes: Int64
    
    public init(label: String, freedMB: Int, freedBytes: Int64? = nil) {
        self.label = label
        self.freedMB = freedMB
        self.freedBytes = freedBytes ?? Int64(freedMB) * 1024 * 1024
    }
}

public struct SkippedCleanupItem: Identifiable, Sendable {
    public let id: UUID = UUID()
    public let label: String
    public let reason: String
}

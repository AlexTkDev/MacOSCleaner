import Foundation

public struct OperationRecord: Identifiable, Codable, Sendable {
    public let id: UUID
    public let itemPath: String
    public let status: String
    public let bytesFreed: Int64
    public let categoryCode: String?
    public let deletionMode: String?
    public let skipped: Int?
    public let failed: Int?

    public init(
        id: UUID,
        itemPath: String,
        status: String,
        bytesFreed: Int64,
        categoryCode: String? = nil,
        deletionMode: String? = nil,
        skipped: Int? = nil,
        failed: Int? = nil
    ) {
        self.id = id
        self.itemPath = itemPath
        self.status = status
        self.bytesFreed = bytesFreed
        self.categoryCode = categoryCode
        self.deletionMode = deletionMode
        self.skipped = skipped
        self.failed = failed
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.itemPath = try container.decode(String.self, forKey: .itemPath)
        self.status = try container.decode(String.self, forKey: .status)
        self.bytesFreed = try container.decode(Int64.self, forKey: .bytesFreed)
        self.categoryCode = try container.decodeIfPresent(String.self, forKey: .categoryCode)
        self.deletionMode = try container.decodeIfPresent(String.self, forKey: .deletionMode)
        self.skipped = try container.decodeIfPresent(Int.self, forKey: .skipped)
        self.failed = try container.decodeIfPresent(Int.self, forKey: .failed)
    }
}

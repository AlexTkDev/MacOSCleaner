import Foundation

public struct OperationRecord: Identifiable, Codable, Sendable {
    public let id: UUID
    public let itemPath: String
    public let status: String
    public let bytesFreed: Int64
    
    public init(id: UUID, itemPath: String, status: String, bytesFreed: Int64) {
        self.id = id
        self.itemPath = itemPath
        self.status = status
        self.bytesFreed = bytesFreed
    }
}

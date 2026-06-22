import Foundation

public struct CleanupTransaction: Identifiable, Codable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let operations: [OperationRecord]
    
    public init(id: UUID, timestamp: Date, operations: [OperationRecord]) {
        self.id = id
        self.timestamp = timestamp
        self.operations = operations
    }
}

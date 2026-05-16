import Foundation

struct CleanupTransaction: Identifiable, Codable, Sendable {
    let id: UUID
    let timestamp: Date
    let operations: [OperationRecord]
}

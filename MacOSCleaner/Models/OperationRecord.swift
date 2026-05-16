import Foundation

struct OperationRecord: Identifiable, Codable, Sendable {
    let id: UUID
    let itemPath: String
    let status: String
    let bytesFreed: Int64
}

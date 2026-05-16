import Foundation

struct CleanupItem: Identifiable, Codable, Sendable {
    let id: UUID
    let name: String
    let path: String
    let size: Int64
    let risk: OperationRisk
}

import Foundation

struct ScanResult: Identifiable, Codable, Sendable {
    let id: UUID
    let timestamp: Date
    let items: [CleanupItem]
    let totalSize: Int64
}

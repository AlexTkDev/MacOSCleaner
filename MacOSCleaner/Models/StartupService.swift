import Foundation

struct StartupService: Identifiable, Codable, Sendable {
    let id: String
    let name: String
    let path: String
    let isEnabled: Bool
}

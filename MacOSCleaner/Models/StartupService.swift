import Foundation

public struct StartupService: Identifiable, Codable, Sendable {
    public let id: String
    public let name: String
    public let path: String
    public let isEnabled: Bool
    
    public init(id: String, name: String, path: String, isEnabled: Bool) {
        self.id = id
        self.name = name
        self.path = path
        self.isEnabled = isEnabled
    }
}

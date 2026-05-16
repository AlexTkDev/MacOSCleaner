import Foundation

enum OperationRisk: String, Codable, Sendable {
    case safe
    case moderate
    case dangerous
    case protected
}

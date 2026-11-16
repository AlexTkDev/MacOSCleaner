import Foundation

public enum OperationRisk: String, Codable, Sendable {
    case safe
    case rebuildable
    case userData = "user_data"
    case protected

    public var localizedTitle: String {
        "risk.\(rawValue)".localized
    }
}

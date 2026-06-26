import Foundation

public enum OperationRisk: String, Codable, Sendable {
    case safe
    case moderate
    case dangerous
    case protected

    public var localizedTitle: String {
        "risk.\(rawValue)".localized
    }
}

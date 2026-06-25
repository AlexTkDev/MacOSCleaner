import Foundation

public struct ConfidenceAssessment: Sendable, Hashable {
    public let evidence: Set<Evidence>
    public let score: Int
    public let tier: ConfidenceTier
    public let missingCritical: [Evidence]
}

public enum ConfidenceTier: String, Sendable, Hashable, CaseIterable, Comparable {
    case ignore
    case possible
    case veryLikely
    case guaranteed

    public var displayKey: String {
        switch self {
        case .ignore: return "uninstaller.tier.ignore"
        case .possible: return "uninstaller.tier.possible"
        case .veryLikely: return "uninstaller.tier.very_likely"
        case .guaranteed: return "uninstaller.tier.guaranteed"
        }
    }

    public static func < (lhs: ConfidenceTier, rhs: ConfidenceTier) -> Bool {
        let order: [ConfidenceTier] = [.ignore, .possible, .veryLikely, .guaranteed]
        guard let l = order.firstIndex(of: lhs), let r = order.firstIndex(of: rhs) else { return false }
        return l < r
    }
}

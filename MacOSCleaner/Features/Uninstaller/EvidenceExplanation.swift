import Foundation

public struct ExplanationContext: Sendable {
    public let bundleID: String?
    public let appName: String
    public let teamID: String?

    public init(bundleID: String?, appName: String, teamID: String?) {
        self.bundleID = bundleID
        self.appName = appName
        self.teamID = teamID
    }
}

public struct EvidenceExplanation: Sendable, Hashable {
    public let evidence: Evidence
    public let title: String
    public let description: String
    public let category: EvidenceCategory

    public init(evidence: Evidence, title: String, description: String) {
        self.evidence = evidence
        self.title = title
        self.description = description
        self.category = evidence.category
    }
}

public enum EvidenceExplanations {
    public static func explanation(for evidence: Evidence, args: CVarArg...) -> EvidenceExplanation {
        let keyPrefix = "uninstaller.evidence.\(evidence.rawValue)"
        let title = "\(keyPrefix).title".localized
        let description = String(format: "\(keyPrefix).description".localized, arguments: args)
        return EvidenceExplanation(evidence: evidence, title: title, description: description)
    }

    public static func explanations(for set: Set<Evidence>, context: ExplanationContext? = nil) -> [EvidenceCategory: [EvidenceExplanation]] {
        var args: [Evidence: CVarArg] = [:]
        if let ctx = context {
            for e in set {
                switch e {
                case .bundleIDPrefix, .spotlightBundleAttr:
                    args[e] = ctx.bundleID ?? ctx.appName
                case .teamID:
                    args[e] = ctx.teamID ?? ""
                case .appNameExact, .appNamePrefix, .executableName, .vendorName:
                    args[e] = ctx.appName
                default:
                    break
                }
            }
        }
        let initialGrouped = Dictionary(grouping: set) { $0.category }
        let grouped = initialGrouped.mapValues { (evidences: [Evidence]) -> [EvidenceExplanation] in
            let explanations = evidences.map { (evidence: Evidence) -> EvidenceExplanation in
                let arg = args[evidence] ?? "" as CVarArg
                return explanation(for: evidence, args: arg)
            }
            return explanations.sorted { $0.evidence.rawValue < $1.evidence.rawValue }
        }
        return grouped
    }
}

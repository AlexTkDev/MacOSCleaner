import Foundation

public struct VerificationReport: Sendable {
    public let leftovers: [ScoredArtifact]
    public let count: Int

    public var hasLeftovers: Bool { count > 0 }

    public init(leftovers: [ScoredArtifact]) {
        self.leftovers = leftovers
        self.count = leftovers.count
    }
}

import Foundation

public struct BaselineFixture: Codable, Sendable {
    public let app: String
    public let bundleID: String
    public let mustFind: [String]
    public let mustNotFind: [String]
    public let developerArtifacts: [String]
    public let scoreFloor: Int

    public init(
        app: String,
        bundleID: String,
        mustFind: [String],
        mustNotFind: [String],
        developerArtifacts: [String],
        scoreFloor: Int
    ) {
        self.app = app
        self.bundleID = bundleID
        self.mustFind = mustFind
        self.mustNotFind = mustNotFind
        self.developerArtifacts = developerArtifacts
        self.scoreFloor = scoreFloor
    }
}

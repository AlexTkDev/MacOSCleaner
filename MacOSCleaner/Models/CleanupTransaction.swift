import Foundation

public struct CleanupTransaction: Identifiable, Codable, Sendable {
    public let id: UUID
    public let timestamp: Date
    public let operations: [OperationRecord]
    public let trigger: CleanupRecord.Trigger?

    public init(
        id: UUID,
        timestamp: Date,
        operations: [OperationRecord],
        trigger: CleanupRecord.Trigger? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.operations = operations
        self.trigger = trigger
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self.timestamp = try container.decode(Date.self, forKey: .timestamp)
        self.operations = try container.decode([OperationRecord].self, forKey: .operations)
        self.trigger = try container.decodeIfPresent(CleanupRecord.Trigger.self, forKey: .trigger)
    }
}

import Foundation
import os.log

private extension Logger {
    static let tmScanner = Logger(subsystem: "com.macoscleaner", category: "TimeMachineScanner")
}

public enum TimeMachineScanner {
    public struct Snapshot: Sendable {
        public let name: String
    }
    
    /// Queries tmutil to list local snapshots and estimates their size.
    public static func listLocalSnapshots(
        commandRunner: any CommandRunning = CommandRunner()
    ) async -> [Snapshot] {
        guard !Task.isCancelled else { return [] }
        guard FileManager.default.fileExists(atPath: "/usr/bin/tmutil") else { return [] }
        do {
            let result = try await commandRunner.run(
                command: "/usr/bin/tmutil",
                arguments: ["listlocalsnapshots", "/"],
                timeout: .seconds(10)
            )
            guard !Task.isCancelled, result.exitCode == 0 else { return [] }

            // tmutil listlocalsnapshots /
            // Snapshots for disk /:
            // com.apple.TimeMachine.2023-10-05-152433.local
            var snapshots: [Snapshot] = []
            for line in result.stdout.components(separatedBy: .newlines) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("com.apple.TimeMachine") {
                    snapshots.append(Snapshot(name: trimmed))
                }
            }
            return snapshots
        } catch {
            Logger.tmScanner.error("Failed to run tmutil listlocalsnapshots: \(error.localizedDescription, privacy: .public)")
            return []
        }
    }
    
    /// Retrieves total purgeable space on the root volume.
    public static func getPurgeableSpaceMB() -> Int {
        do {
            let url = URL(fileURLWithPath: "/")
            let values = try url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey])
            if let important = values.volumeAvailableCapacityForImportantUsage,
               let available = values.volumeAvailableCapacity {
                // Purgeable space can be roughly estimated as (important - available)
                let purgeable = important - Int64(available)
                if purgeable > 0 {
                    return Int(purgeable / (1024 * 1024))
                }
            }
        } catch {
            Logger.tmScanner.warning("Could not get purgeable space: \(error.localizedDescription, privacy: .public)")
        }
        return 0
    }
}

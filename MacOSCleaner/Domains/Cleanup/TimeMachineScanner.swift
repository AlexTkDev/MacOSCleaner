import Foundation
import os.log

private extension Logger {
    static let tmScanner = Logger(subsystem: "com.macoscleaner", category: "TimeMachineScanner")
}

public actor TimeMachineScanner {
    public struct Snapshot: Sendable {
        public let name: String
        public let estimatedSizeMB: Int
    }
    
    /// Queries tmutil to list local snapshots and estimates their size.
    public static func listLocalSnapshots() async -> [Snapshot] {
        return await Task.detached {
            let task = Process()
            task.launchPath = "/usr/bin/tmutil"
            task.arguments = ["listlocalsnapshots", "/"]
            
            let pipe = Pipe()
            task.standardOutput = pipe
            
            do {
                try task.run()
                task.waitUntilExit()
                
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                guard let output = String(data: data, encoding: .utf8) else {
                    return []
                }
                
                // tmutil listlocalsnapshots /
                // Snapshots for disk /:
                // com.apple.TimeMachine.2023-10-05-152433.local
                
                var snapshots: [Snapshot] = []
                let lines = output.components(separatedBy: .newlines)
                for line in lines {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if trimmed.hasPrefix("com.apple.TimeMachine") {
                        // We cannot easily determine exact size of individual snapshots via CLI,
                        // so we estimate a fixed minimal size for representation or fetch total purgeable.
                        // Let's use a dummy size of 0 for individual items and rely on system purgeable size.
                        snapshots.append(Snapshot(name: trimmed, estimatedSizeMB: 0))
                    }
                }
                
                return snapshots
            } catch {
                Logger.tmScanner.error("Failed to run tmutil listlocalsnapshots: \(error.localizedDescription, privacy: .public)")
                return []
            }
        }.value
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

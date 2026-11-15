import Foundation

public actor CommandCache {
    private var known: Set<String> = []
    private var checked: Set<String> = []

    public init() {}

    public func resolve(_ command: String, runner: any CommandRunning) async -> Bool {
        if known.contains(command) { return true }
        if checked.contains(command) { return false }
        let result = await runner.commandExists(command)
        if result { known.insert(command) }
        checked.insert(command)
        return result
    }
}

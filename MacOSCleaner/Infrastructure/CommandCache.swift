import Foundation

public actor CommandCache {
    private var known: Set<String> = []
    private var checked: Set<String> = []

    public init() {}

    public func exists(_ command: String) -> Bool {
        known.contains(command)
    }

    public func markExists(_ command: String) {
        known.insert(command)
        checked.insert(command)
    }

    public func markMissing(_ command: String) {
        checked.insert(command)
    }

    public func wasChecked(_ command: String) -> Bool {
        checked.contains(command)
    }

    public func isCheckedAndMissing(_ command: String) -> Bool {
        checked.contains(command) && !known.contains(command)
    }

    public func resolve(_ command: String, runner: any CommandRunning) async -> Bool {
        if known.contains(command) { return true }
        if checked.contains(command) { return false }
        let result = await runner.commandExists(command)
        if result { known.insert(command) }
        checked.insert(command)
        return result
    }

    public func clear() {
        known.removeAll()
        checked.removeAll()
    }
}

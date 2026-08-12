import Foundation
import AppKit

/// Controls the startup update sheet (FDA-style present / snooze).
@Observable
public final class UpdatePromptController {
    public var showSheet = false

    private let dismissedVersionKey = "com.macoscleaner.updateDismissedVersion"

    public init() {}

    public func shouldPresent(_ update: AvailableUpdate) -> Bool {
        let dismissed = UserDefaults.standard.string(forKey: dismissedVersionKey)
        return dismissed != update.version
    }

    public func presentIfNeeded(update: AvailableUpdate?, fdaShowing: Bool) {
        guard let update else { return }
        guard !fdaShowing else { return }
        guard shouldPresent(update) else { return }
        showSheet = true
    }

    public func dismissTemporarily() {
        showSheet = false
    }

    public func dismissForVersion(_ version: String) {
        UserDefaults.standard.set(version, forKey: dismissedVersionKey)
        showSheet = false
    }

    public static func open(_ update: AvailableUpdate) {
        NSWorkspace.shared.open(update.openURL)
    }

    public static func openReleases() {
        NSWorkspace.shared.open(UpdateChecker.releasesURL)
    }
}

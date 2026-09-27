// Copyright (C) 2026 AlexTkDev
// Licensed under GNU General Public License v3.0 (GPLv3)

import Foundation
import LocalAuthentication
import os.log

private extension Logger {
    static let maintenance = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.macos-cleaner", category: "SystemMaintenance")
}

@MainActor
@Observable
public final class SystemMaintenanceService {
    public private(set) var isTouchIDHardwareAvailable: Bool = false
    public private(set) var isTouchIDForSudoEnabled: Bool = false
    public private(set) var isReindexingSpotlight: Bool = false
    public private(set) var spotlightStatusMessage: String? = nil
    public private(set) var errorMessage: String? = nil

    private let pamSudoLocalPath = "/private/etc/pam.d/sudo_local"

    public init() {
        refreshTouchIDStatus()
    }

    public func refreshTouchIDStatus() {
        let context = LAContext()
        var error: NSError?
        self.isTouchIDHardwareAvailable = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        self.isTouchIDForSudoEnabled = checkTouchIDForSudo()
    }

    private func checkTouchIDForSudo() -> Bool {
        guard FileManager.default.fileExists(atPath: pamSudoLocalPath) else {
            return false
        }
        guard let content = try? String(contentsOfFile: pamSudoLocalPath, encoding: .utf8) else {
            return false
        }
        for line in content.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if !trimmed.hasPrefix("#") && trimmed.contains("pam_tid.so") {
                return true
            }
        }
        return false
    }

    public func rebuildSpotlightIndex() async throws {
        isReindexingSpotlight = true
        errorMessage = nil
        spotlightStatusMessage = nil
        defer { isReindexingSpotlight = false }

        // mdutil -E -i on / re-enables indexing and erases the store on the root volume
        let cmd = "/usr/bin/mdutil -E -i on /"
        do {
            let output = try await PrivilegedTaskRunner.runAsAdmin(command: cmd)
            spotlightStatusMessage = "settings_spotlight_reindex_success".localized
            Logger.maintenance.info("Spotlight index rebuilt: \(output, privacy: .public)")
        } catch {
            self.errorMessage = error.localizedDescription
            Logger.maintenance.error("Spotlight rebuild failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    public private(set) var isPurgingAssessmentCache: Bool = false
    public private(set) var assessmentCacheStatusMessage: String? = nil

    public func purgeAssessmentCache() async throws {
        isPurgingAssessmentCache = true
        errorMessage = nil
        assessmentCacheStatusMessage = nil
        defer { isPurgingAssessmentCache = false }

        let cmd = "/usr/sbin/spctl --purge"
        do {
            let output = try await PrivilegedTaskRunner.runAsAdmin(command: cmd)
            assessmentCacheStatusMessage = "settings_spctl_purge_success".localized
            Logger.maintenance.info("Gatekeeper assessment cache purged: \(output, privacy: .public)")
        } catch {
            self.errorMessage = error.localizedDescription
            Logger.maintenance.error("Gatekeeper cache purge failed: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }
}

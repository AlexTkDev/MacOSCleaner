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
    private let pamSudoLocalTemplatePath = "/private/etc/pam.d/sudo_local.template"

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

    public func setTouchIDForSudo(enabled: Bool) async throws {
        errorMessage = nil

        let currentContent = (try? String(contentsOfFile: pamSudoLocalPath, encoding: .utf8))
            ?? (try? String(contentsOfFile: pamSudoLocalTemplatePath, encoding: .utf8))

        let content: String
        if enabled {
            if let current = currentContent {
                if current.contains("pam_tid.so") {
                    content = current.replacingOccurrences(
                        of: #"^[#\s]*(auth\s+sufficient\s+pam_tid\.so)"#,
                        with: "auth       sufficient     pam_tid.so",
                        options: .regularExpression
                    )
                } else {
                    content = "auth       sufficient     pam_tid.so\n" + current
                }
            } else {
                content = "# sudo_local: local PAM configuration for sudo\nauth       sufficient     pam_tid.so\n"
            }
        } else {
            if let current = currentContent {
                content = current.replacingOccurrences(
                    of: #"^(auth\s+sufficient\s+pam_tid\.so)"#,
                    with: "#$1",
                    options: .regularExpression
                )
            } else {
                content = "# sudo_local: local PAM configuration for sudo\n#auth       sufficient     pam_tid.so\n"
            }
        }

        // Encode content in Base64 to avoid any quoting, newline, or temp-file sandbox issues
        let base64 = Data(content.utf8).base64EncodedString()
        let command = "/bin/chmod 644 \(pamSudoLocalPath) 2>/dev/null || true; /bin/echo '\(base64)' | /usr/bin/base64 -d | /usr/bin/tee \(pamSudoLocalPath) > /dev/null; /bin/chmod 444 \(pamSudoLocalPath); /usr/sbin/chown root:wheel \(pamSudoLocalPath)"

        do {
            _ = try await PrivilegedTaskRunner.runAsAdmin(command: command)
            refreshTouchIDStatus()
            Logger.maintenance.info("Touch ID for sudo set to \(enabled)")
        } catch {
            self.errorMessage = error.localizedDescription
            Logger.maintenance.error("Failed to set Touch ID for sudo: \(error.localizedDescription, privacy: .public)")
            throw error
        }
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
}

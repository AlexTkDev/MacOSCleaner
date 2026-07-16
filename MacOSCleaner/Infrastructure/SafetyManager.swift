import Foundation

public enum SafetyError: Error, Equatable {
    case pathNormalizationFailed
    case symlinkEscapeAttempted
    case protectedPath(String)
}

public struct SafetyManager: Sendable {
    private let refuseList: [String]
    private let allowedExceptions: [String]

    public init(allowedExceptions: [String] = []) {
        let home = NSHomeDirectory()
        self.refuseList = [
            "/",
            "/System",
            "/Library",
            "/usr",
            "/bin",
            "/sbin",
            "/private",
            "/etc",
            "/var",
            "/tmp",
            "\(home)/.ssh",
            "\(home)/.gnupg",
            "\(home)/Documents",
            // Sensitive user data - never clean
            "\(home)/Library/Keychains",
            "\(home)/Library/Mail",
            "\(home)/Library/Calendars",
            "\(home)/Library/Reminders",
            "\(home)/Library/Contacts",
            "\(home)/Library/Group Containers",
            "\(home)/Library/Containers/com.apple.mail",
            // Passwords and credentials
            "\(home)/Library/Application Support/Chrome/Default/Login Data",
            "\(home)/Library/Application Support/Chrome/Default/Cookies",
            "\(home)/Library/Application Support/Google/Chrome/Default/Login Data",
            "\(home)/Library/Application Support/Firefox/Profiles",
            // Critical system-level user data
            "\(home)/Library/Preferences",
        ]
        
        let defaultExceptions = [
            "\(home)/Library",
            "/Library/Application Support",
            "/Library/LaunchAgents",
            "/Library/LaunchDaemons",
            "/Library/Receipts",
            "/Library/Internet Plug-Ins",
            "/private/var/folders",
            "/private/tmp",
            "/tmp",
            "/usr/local",
            "\(home)/Library/Application Support/MacOSCleaner",
            "\(home)/Library/Application Scripts/input.MacOSCleaner",
            // Safe cache directories
            "\(home)/Library/Caches",
            "\(home)/Library/Developer",
            "\(home)/Library/Logs",
            "\(home)/Library/Application Support",
            "\(home)/Library/Containers",
            "\(home)/.cache",
            "\(home)/.config",
            "\(home)/.local",
            "\(home)/.gradle",
            "\(home)/.pub-cache",
            "\(home)/.dartServer",
            "\(home)/.android",
            "\(home)/Library/Android",
            // Browser caches (safe to clean)
            "\(home)/Library/Safari",
            "\(home)/Library/WebKit",
            "\(home)/Library/Application Support/Google/Chrome",
            "\(home)/Library/Application Support/Chrome",
        ]
        
        self.allowedExceptions = defaultExceptions + allowedExceptions
    }

    public func validate(url: URL) throws {
        guard url.isFileURL else {
            throw SafetyError.pathNormalizationFailed
        }

        let standardized = url.standardizedFileURL
        let path = standardized.path
        
        guard !path.isEmpty else {
            throw SafetyError.pathNormalizationFailed
        }

        let resolvedPath = standardized.resolvingSymlinksInPath().path

        let pathsToCheck = [path, resolvedPath]
        
        for p in pathsToCheck {
            let isException = allowedExceptions.contains { exception in
                p == exception || p.hasPrefix(exception + "/")
            }
            
            if isException {
                continue
            }

            for refused in refuseList {
                let isExactMatch = (p == refused)
                let isSubdirectory = p.hasPrefix(refused + "/")
                
                if isExactMatch || isSubdirectory {
                    throw SafetyError.protectedPath(refused)
                }
            }
        }
    }
}

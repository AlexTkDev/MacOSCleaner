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
            "\(home)/Documents"
        ]
        
        let defaultExceptions = [
            "\(home)/Library",
            "/Library/LaunchAgents",
            "/Library/LaunchDaemons",
            "/private/var/folders",
            "/private/tmp",
            "/tmp",
            "/usr/local",
            "\(home)/Library/Application Support/MacOSCleaner",
            "\(home)/Library/Application Scripts/input.MacOSCleaner"
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
            // Check if path is explicitly allowed
            let isException = allowedExceptions.contains { exception in
                p == exception || p.hasPrefix(exception + "/")
            }
            
            if isException {
                continue
            }

            for refused in refuseList {
                let isExactMatch = (p == refused)
                let isSubdirectory = p.hasPrefix(refused == "/" ? "//" : refused + "/")
                
                if isExactMatch || isSubdirectory {
                    throw SafetyError.protectedPath(refused)
                }
            }
        }
    }
}

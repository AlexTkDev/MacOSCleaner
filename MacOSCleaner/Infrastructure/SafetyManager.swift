import Foundation

public enum SafetyError: Error, Equatable {
    case pathNormalizationFailed
    case symlinkEscapeAttempted
    case protectedPath(String)
}

public struct SafetyManager: Sendable {
    private let refuseList: [String]

    public init() {
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

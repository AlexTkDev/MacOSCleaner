import Foundation
import SwiftUI
import AppKit

public actor UninstallerService {
    private let fileManager: FileManager
    private let safetyManager: SafetyManager
    private let trashManager: TrashManager

    public init(
        fileManager: FileManager = .default,
        safetyManager: SafetyManager = SafetyManager(),
        trashManager: TrashManager = TrashManager()
    ) {
        self.fileManager = fileManager
        self.safetyManager = safetyManager
        self.trashManager = trashManager
    }

    public struct RelatedFile: Identifiable, Sendable, Hashable {
        public let id = UUID()
        public let url: URL
        public var isSelected: Bool = true
        public let size: Int64
        
        public func hash(into hasher: inout Hasher) { hasher.combine(id) }
        public static func == (lhs: RelatedFile, rhs: RelatedFile) -> Bool { lhs.id == rhs.id }
    }

    public struct AppInfo: Identifiable, Sendable, Hashable {
        public let id = UUID()
        public let url: URL
        public let bundleID: String?
        public let name: String
        public var relatedFiles: [RelatedFile] = []
        
        public var size: Int64 = 0
        public var version: String = ""
        public var lastUsed: Date? = nil
        public var icon: NSImage? = nil
        
        public func hash(into hasher: inout Hasher) { hasher.combine(id) }
        public static func == (lhs: AppInfo, rhs: AppInfo) -> Bool { lhs.id == rhs.id }
        
        public var totalSize: Int64 {
            let relatedSize = relatedFiles.filter(\.isSelected).reduce(0) { $0 + $1.size }
            return size + relatedSize
        }
    }

    public func scanAllApplications() async throws -> [AppInfo] {
        let appDirs = [
            URL(fileURLWithPath: "/Applications"),
            fileManager.urls(for: .applicationDirectory, in: .userDomainMask)[0]
        ]
        
        return try await withThrowingTaskGroup(of: AppInfo?.self) { group in
            for dir in appDirs {
                guard let contents = try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
                for url in contents where url.pathExtension == "app" {
                    group.addTask {
                        return try? await self.scan(appURL: url)
                    }
                }
            }
            
            var apps: [AppInfo] = []
            for try await app in group {
                if let app = app {
                    apps.append(app)
                }
            }
            return apps.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
        }
    }

    public func scan(appURL: URL) async throws -> AppInfo {
        try safetyManager.validate(url: appURL)
        
        let bundle = Bundle(url: appURL)
        let bundleID = bundle?.bundleIdentifier
        let appName = appURL.deletingPathExtension().lastPathComponent
        let infoDictionary = bundle?.infoDictionary
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? 
                     infoDictionary?["CFBundleVersion"] as? String ?? "N/A"
        
        let size = await getDirectorySize(url: appURL)
        let icon = NSWorkspace.shared.icon(forFile: appURL.path)
        
        let mdItem = MDItemCreate(nil, appURL.path as CFString)
        let lastUsed = MDItemCopyAttribute(mdItem, kMDItemLastUsedDate) as? Date
        
        var related: [RelatedFile] = []
        let searchPatterns = [bundleID, appName].compactMap { $0 }.filter { !$0.isEmpty }
        
        if !searchPatterns.isEmpty {
            let libraryPaths = [
                "~/Library/Application Support",
                "~/Library/Caches",
                "~/Library/Containers",
                "~/Library/Cookies",
                "~/Library/Logs",
                "~/Library/Preferences",
                "~/Library/Saved Application State",
                "~/Library/LaunchAgents",
                "/Library/Application Support",
                "/Library/Caches",
                "/Library/LaunchAgents",
                "/Library/LaunchDaemons",
                "/Library/Preferences",
                "/Library/PrivilegedHelperTools"
            ]
            
            for path in libraryPaths {
                let expandedPath = (path as NSString).expandingTildeInPath
                let folderURL = URL(fileURLWithPath: expandedPath)
                
                guard let contents = try? fileManager.contentsOfDirectory(at: folderURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { continue }
                
                for fileURL in contents {
                    let fileName = fileURL.lastPathComponent
                    let matches = searchPatterns.contains { pattern in
                        fileName.localizedCaseInsensitiveContains(pattern)
                    }
                    
                    if matches {
                        let fileSize = await getDirectorySize(url: fileURL)
                        related.append(RelatedFile(url: fileURL, size: fileSize))
                    }
                }
            }
        }
        
        return AppInfo(
            url: appURL,
            bundleID: bundleID,
            name: appName,
            relatedFiles: related,
            size: size,
            version: version,
            lastUsed: lastUsed,
            icon: icon
        )
    }

    public func uninstall(app: AppInfo) async throws {
        _ = try await trashManager.trashItem(at: app.url)
        for file in app.relatedFiles where file.isSelected {
            try? _ = await trashManager.trashItem(at: file.url)
        }
    }
    
    private func getDirectorySize(url: URL) async -> Int64 {
        var size: Int64 = 0
        let enumerator = fileManager.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey], options: [])
        while let fileURL = enumerator?.nextObject() as? URL {
            let resourceValues = try? fileURL.resourceValues(forKeys: [.fileSizeKey])
            size += Int64(resourceValues?.fileSize ?? 0)
        }
        return size
    }
}

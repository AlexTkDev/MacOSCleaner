import Foundation
import SwiftUI

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
        
        public func hash(into hasher: inout Hasher) { hasher.combine(id) }
        public static func == (lhs: RelatedFile, rhs: RelatedFile) -> Bool { lhs.id == rhs.id }
    }

    public struct AppInfo: Identifiable, Sendable, Hashable {
        public let id = UUID()
        public let url: URL
        public let bundleID: String?
        public var relatedFiles: [RelatedFile] = []
        
        public var size: Int64 = 0
        public var version: String = ""
        public var lastUsed: Date? = nil
        
        public func hash(into hasher: inout Hasher) { hasher.combine(id) }
        public static func == (lhs: AppInfo, rhs: AppInfo) -> Bool { lhs.id == rhs.id }
    }

    public func scanAllApplications() throws -> [AppInfo] {
        let appDirs = [
            URL(fileURLWithPath: "/Applications"),
            fileManager.urls(for: .applicationDirectory, in: .userDomainMask)[0]
        ]
        
        var apps: [AppInfo] = []
        for dir in appDirs {
            guard let contents = try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { continue }
            for url in contents where url.pathExtension == "app" {
                if let app = try? scan(appURL: url) {
                    apps.append(app)
                }
            }
        }
        return apps
    }

    public func scan(appURL: URL) throws -> AppInfo {
        try safetyManager.validate(url: appURL)
        
        let bundle = Bundle(url: appURL)
        let bundleID = bundle?.bundleIdentifier
        let infoDictionary = bundle?.infoDictionary
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "N/A"
        
        let attributes = try fileManager.attributesOfItem(atPath: appURL.path)
        let size = attributes[.size] as? Int64 ?? 0
        
        let mdItem = MDItemCreate(nil, appURL.path as CFString)
        let lastUsed = MDItemCopyAttribute(mdItem, kMDItemLastUsedDate) as? Date
        
        var related: [RelatedFile] = []
        if let id = bundleID {
            let library = fileManager.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            let paths = [
                library.appendingPathComponent("Application Support").appendingPathComponent(id),
                library.appendingPathComponent("Preferences").appendingPathComponent("\(id).plist"),
                library.appendingPathComponent("Caches").appendingPathComponent(id)
            ]
            
            for path in paths {
                if fileManager.fileExists(atPath: path.path) {
                    related.append(RelatedFile(url: path))
                }
            }
        }
        
        return AppInfo(url: appURL, bundleID: bundleID, relatedFiles: related, size: size, version: version, lastUsed: lastUsed)
    }

    public func uninstall(app: AppInfo) async throws {
        _ = try await trashManager.trashItem(at: app.url)
        for file in app.relatedFiles where file.isSelected {
            try? _ = await trashManager.trashItem(at: file.url)
        }
    }
}

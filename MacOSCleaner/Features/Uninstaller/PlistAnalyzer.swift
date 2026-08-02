import Foundation

public actor PlistAnalyzer {
    private let fileManager: FileManager
    private let plistCache: PlistContentCache

    public init(
        fileManager: FileManager = .default,
        plistCache: PlistContentCache = PlistContentCache()
    ) {
        self.fileManager = fileManager
        self.plistCache = plistCache
    }

    public static let searchDirectories: [String] = [
        NormalizedPath.joinHome(NSHomeDirectory(), "Library/Preferences"),
        NormalizedPath.joinHome(NSHomeDirectory(), "Library/Preferences/ByHost"),
        NormalizedPath.joinHome(NSHomeDirectory(), "Library/Containers"),
        NormalizedPath.joinHome(NSHomeDirectory(), "Library/Group Containers"),
        "/Library/Preferences",
        "/Library/Managed Preferences",
    ]

    public func analyze(identity: AppIdentity) async -> [(url: URL, evidence: ArtifactEvidence)] {
        var results: [(URL, ArtifactEvidence)] = []

        for dir in Self.searchDirectories {
            let url = NormalizedPath.url(dir, isDirectory: true)
            guard fileManager.fileExists(atPath: url.path),
                  let contents = try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
            else { continue }

            for item in contents where item.pathExtension == "plist" || item.lastPathComponent.hasSuffix(".plist") {
                let size = (try? item.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
                guard size > 0, size < 512 * 1024 else { continue }

                guard let content = await plistCache.getContent(url: item) else { continue }
                let lower = content.lowercased()

                var foundSources: [EvidenceSource] = []

                if lower.contains(identity.bundleID.lowercased()) {
                    foundSources.append(.plistContent)
                }
                if let name = identity.bundleName, lower.contains(name.lowercased()) {
                    foundSources.append(.plistContent)
                }
                if lower.contains(identity.appName.lowercased()) {
                    foundSources.append(.plistContent)
                }
                if let devName = identity.signingAuthority?.lowercased(), lower.contains(devName) {
                    foundSources.append(.plistContent)
                }

                for source in foundSources {
                    let name = item.lastPathComponent
                    if !name.contains(identity.bundleID) && !name.contains(identity.appName)
                        && !identity.vendorNames.contains(where: { name.contains($0) }) {
                        if name.contains("com.apple.") {
                            results.append((item, ArtifactEvidence(source: .foreignBundleID, weight: -200)))
                            continue
                        }
                    }
                    results.append((item, ArtifactEvidence(source: source, weight: 80)))
                }
            }
        }

        return results
    }
}

import Foundation

public enum DeveloperComponentsDetector {
    public static func detect(
        appName: String,
        bundleID: String?,
        fileManager: FileManager = .default,
        homeDirectory: URL? = nil,
        fileSystemContext: FileSystemContext? = nil
    ) async -> [UninstallerService.RelatedCleanupComponent] {
        let fm = fileManager
        let home = (fileSystemContext?.homeDirectory ?? homeDirectory ?? fm.homeDirectoryForCurrentUser).path
        var components: [UninstallerService.RelatedCleanupComponent] = []
        let lowerName = appName.lowercased()
        let lowerID = bundleID?.lowercased() ?? ""

        if lowerName.contains("android studio") || lowerID.contains("android.studio") {
            // Whole ~/Library/Android (SDK + NDK + extras), not only …/sdk.
            let androidRootURL = NormalizedPath.url(NormalizedPath.joinHome(home, "Library/Android"), isDirectory: true)
            if fm.fileExists(atPath: androidRootURL.path) {
                let androidSize = getDirectorySize(url: androidRootURL)
                if androidSize > 0 {
                    components.append(UninstallerService.RelatedCleanupComponent(
                        title: "developer.android_sdk".localized,
                        category: .androidSDK,
                        sizeBytes: androidSize,
                        url: androidRootURL,
                        isSelected: false
                    ))
                }
            }
            let gradleURL = NormalizedPath.url(NormalizedPath.joinHome(home, ".gradle"), isDirectory: true)
            if fm.fileExists(atPath: gradleURL.path) {
                let gradleSize = getDirectorySize(url: gradleURL)
                if gradleSize > 0 {
                    components.append(UninstallerService.RelatedCleanupComponent(
                        title: "developer.gradle_cache".localized,
                        category: .gradleMaven,
                        sizeBytes: gradleSize,
                        url: gradleURL,
                        isSelected: true
                    ))
                }
            }
            let androidDataURL = NormalizedPath.url(NormalizedPath.joinHome(home, ".android"), isDirectory: true)
            if fm.fileExists(atPath: androidDataURL.path) {
                let androidDataSize = getDirectorySize(url: androidDataURL)
                if androidDataSize > 0 {
                    components.append(UninstallerService.RelatedCleanupComponent(
                        title: "developer.android_data".localized,
                        category: .androidCaches,
                        sizeBytes: androidDataSize,
                        url: androidDataURL,
                        isSelected: true
                    ))
                }
            }
        }

        if lowerID == "com.apple.dt.xcode" || (lowerName == "xcode" && lowerID.hasPrefix("com.apple.dt")) {
            let derivedURL = NormalizedPath.url(
                NormalizedPath.joinHome(home, "Library/Developer/Xcode/DerivedData"),
                isDirectory: true
            )
            if fm.fileExists(atPath: derivedURL.path) {
                let derivedSize = getDirectorySize(url: derivedURL)
                if derivedSize > 0 {
                    components.append(UninstallerService.RelatedCleanupComponent(
                        title: "developer.xcode_derived_data".localized,
                        category: .xcode,
                        sizeBytes: derivedSize,
                        url: derivedURL,
                        isSelected: true
                    ))
                }
            }
            let simURL = NormalizedPath.url(
                NormalizedPath.joinHome(home, "Library/Developer/CoreSimulator"),
                isDirectory: true
            )
            if fm.fileExists(atPath: simURL.path) {
                let simSize = getDirectorySize(url: simURL)
                if simSize > 0 {
                    components.append(UninstallerService.RelatedCleanupComponent(
                        title: "developer.ios_simulators".localized,
                        category: .iosSimulators,
                        sizeBytes: simSize,
                        url: simURL,
                        isSelected: true
                    ))
                }
            }
        }

        if lowerName == "flutter" || lowerID.contains("flutter") {
            let flutterURL = NormalizedPath.url(NormalizedPath.joinHome(home, ".pub-cache"), isDirectory: true)
            if fm.fileExists(atPath: flutterURL.path) {
                let flutterSize = getDirectorySize(url: flutterURL)
                if flutterSize > 0 {
                    components.append(UninstallerService.RelatedCleanupComponent(
                        title: "developer.flutter_cache".localized,
                        category: .flutterDart, sizeBytes: flutterSize,
                        url: flutterURL,
                        isSelected: false
                    ))
                }
            }
        }

        if lowerName.contains("orbstack") || lowerID == "dev.orbstack" || lowerName.contains("docker") || lowerID == "com.docker.docker" {
            let dockerURL = NormalizedPath.url(
                NormalizedPath.joinHome(home, "Library/Containers/com.docker.docker"),
                isDirectory: true
            )
            if fm.fileExists(atPath: dockerURL.path) {
                let dockerSize = getDirectorySize(url: dockerURL)
                if dockerSize > 0 {
                    components.append(UninstallerService.RelatedCleanupComponent(
                        title: "developer.docker".localized,
                        category: .docker, sizeBytes: dockerSize,
                        url: dockerURL,
                        isSelected: false
                    ))
                }
            }
        }

        if lowerName == "homebrew" || lowerID == "com.homebrew" {
            let brewURL = NormalizedPath.url("/opt/homebrew", isDirectory: true)
            if fm.fileExists(atPath: brewURL.path) {
                let brewSize = getDirectorySize(url: brewURL)
                if brewSize > 0 {
                    components.append(UninstallerService.RelatedCleanupComponent(
                        title: "developer.homebrew".localized,
                        category: .packageManagers, sizeBytes: brewSize,
                        url: brewURL,
                        isSelected: false
                    ))
                }
            }
        }

        return components.uniquedByPath()
    }

    private static func getDirectorySize(url: URL) -> Int64 {
        FileManager.default.getPhysicalDirectorySize(url: url, excludedPaths: [])
    }
}

private extension Array where Element == UninstallerService.RelatedCleanupComponent {
    func uniquedByPath() -> [UninstallerService.RelatedCleanupComponent] {
        var seen = Set<String>()
        var result: [UninstallerService.RelatedCleanupComponent] = []
        for component in self {
            let pathKey = NormalizedPath.key(component.url)
            guard seen.insert(pathKey).inserted else { continue }
            result.append(component)
        }
        return result
    }
}

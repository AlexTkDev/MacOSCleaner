import Foundation

public enum DeveloperComponentsDetector {
    public static func detect(
        appName: String,
        bundleID: String?,
        fileManager: FileManager = .default
    ) async -> [UninstallerService.RelatedCleanupComponent] {
        let fm = fileManager
        let home = NSHomeDirectory()
        var components: [UninstallerService.RelatedCleanupComponent] = []
        let lowerName = appName.lowercased()
        let lowerID = bundleID?.lowercased() ?? ""

        if lowerName.contains("android studio") || lowerID.contains("android.studio") {
            let sdkURL = URL(fileURLWithPath: "\(home)/Library/Android/sdk")
            if fm.fileExists(atPath: sdkURL.path) {
                let sdkSize = getDirectorySize(url: sdkURL)
                if sdkSize > 0 {
                    components.append(UninstallerService.RelatedCleanupComponent(
                        title: "developer.android_sdk".localized,
                        category: .androidSDK, sizeBytes: sdkSize,
                        url: sdkURL
                    ))
                }
            }
            let gradleURL = URL(fileURLWithPath: "\(home)/.gradle")
            if fm.fileExists(atPath: gradleURL.path) {
                let gradleSize = getDirectorySize(url: gradleURL)
                if gradleSize > 0 {
                    components.append(UninstallerService.RelatedCleanupComponent(
                        title: "developer.gradle_cache".localized,
                        category: .gradleMaven, sizeBytes: gradleSize,
                        url: gradleURL
                    ))
                }
            }
        }

        if lowerID == "com.apple.dt.xcode" || (lowerName == "xcode" && lowerID.hasPrefix("com.apple.dt")) {
            let derivedURL = URL(fileURLWithPath: "\(home)/Library/Developer/Xcode/DerivedData")
            if fm.fileExists(atPath: derivedURL.path) {
                let derivedSize = getDirectorySize(url: derivedURL)
                if derivedSize > 0 {
                    components.append(UninstallerService.RelatedCleanupComponent(
                        title: "developer.xcode_derived_data".localized,
                        category: .xcode, sizeBytes: derivedSize,
                        url: derivedURL
                    ))
                }
            }
            let simURL = URL(fileURLWithPath: "\(home)/Library/Developer/CoreSimulator")
            if fm.fileExists(atPath: simURL.path) {
                let simSize = getDirectorySize(url: simURL)
                if simSize > 0 {
                    components.append(UninstallerService.RelatedCleanupComponent(
                        title: "developer.ios_simulators".localized,
                        category: .iosSimulators, sizeBytes: simSize,
                        url: simURL
                    ))
                }
            }
        }

        if lowerName == "flutter" || lowerID.contains("flutter") {
            let flutterURL = URL(fileURLWithPath: "\(home)/.pub-cache")
            if fm.fileExists(atPath: flutterURL.path) {
                let flutterSize = getDirectorySize(url: flutterURL)
                if flutterSize > 0 {
                    components.append(UninstallerService.RelatedCleanupComponent(
                        title: "developer.flutter_cache".localized,
                        category: .flutterDart, sizeBytes: flutterSize,
                        url: flutterURL
                    ))
                }
            }
        }

        if lowerName.contains("orbstack") || lowerID == "dev.orbstack" || lowerName.contains("docker") || lowerID == "com.docker.docker" {
            let dockerURL = URL(fileURLWithPath: "\(home)/Library/Containers/com.docker.docker")
            if fm.fileExists(atPath: dockerURL.path) {
                let dockerSize = getDirectorySize(url: dockerURL)
                if dockerSize > 0 {
                    components.append(UninstallerService.RelatedCleanupComponent(
                        title: "developer.docker".localized,
                        category: .docker, sizeBytes: dockerSize,
                        url: dockerURL
                    ))
                }
            }
        }

        if lowerName == "homebrew" || lowerID == "com.homebrew" {
            let brewURL = URL(fileURLWithPath: "/opt/homebrew")
            if fm.fileExists(atPath: brewURL.path) {
                let brewSize = getDirectorySize(url: brewURL)
                if brewSize > 0 {
                    components.append(UninstallerService.RelatedCleanupComponent(
                        title: "developer.homebrew".localized,
                        category: .packageManagers, sizeBytes: brewSize,
                        url: brewURL
                    ))
                }
            }
        }

        return components
    }

    private static func getDirectorySize(url: URL) -> Int64 {
        FileManager.default.getDirectorySize(url: url, excludedPaths: [])
    }
}

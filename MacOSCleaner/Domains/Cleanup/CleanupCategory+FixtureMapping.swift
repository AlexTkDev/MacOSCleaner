import Foundation

extension CleanupCategory {
    /// Shown in preview, never wiped as a whole. Selected leaves go to Trash.
    public static let reviewOnly: [CleanupCategory] = [
        .oldBackups, .iosBackups, .aiModels, .installerPackages, .largeFiles, .projectBuildArtifacts
    ]

    /// Categories backed by native CLI tools that reclaim space directly without Trash.
    public var isDirectCommandCleanup: Bool {
        switch self {
        case .packageManagers, .docker, .iosSimulators, .timeMachineSnapshots, .dnsFlush, .fontCache:
            return true
        default:
            return false
        }
    }

    public var localizedTitle: String {
        "category.\(rawValue)".localized
    }

    public var iconName: String {
        switch self {
        case .appCaches, .systemCaches, .appContainers, .dotfileCaches, .dynamicCacheDiscovery:
            return "internaldrive"
        case .packageManagers, .gradleMaven, .flutterDart, .xcode, .iosSimulators,
             .androidCaches, .androidSDK, .ideCaches, .languageCaches,
             .swiftPMCache, .carthageCache, .projectBuildArtifacts:
            return "hammer"
        case .browserCaches, .chromeExtraCaches:
            return "globe"
        case .messagingMedia, .teamsCache:
            return "bubble.left.and.bubble.right"
        case .docker:
            return "shippingbox"
        case .userLogs, .crashReporter, .savedAppState, .sharedFileLists:
            return "doc.plaintext"
        case .largeFiles, .scatteredJunk:
            return "doc.badge.ellipsis"
        case .timeMachineSnapshots, .iosBackups, .oldBackups:
            return "clock.arrow.circlepath"
        case .mailDownloads:
            return "envelope"
        case .photosCache:
            return "photo.on.rectangle"
        case .aiModels:
            return "sparkles"
        case .installerPackages:
            return "shippingbox.fill"
        case .dnsFlush, .fontCache:
            return "gearshape.2"
        default:
            return "folder.fill"
        }
    }

    public static func iconName(forResultLabel label: String) -> String {
        if label == "trash_user_label".localized {
            return "trash"
        }
        for category in CleanupCategory.allCases where category.previewLabels.contains(label) {
            return category.iconName
        }
        return "sparkles"
    }

    /// Maps scanner/engine group labels to the localized category title used in the preview UI.
    public static func localizedGroupTitle(for scannerLabel: String) -> String {
        for category in CleanupCategory.allCases where category.previewLabels.contains(scannerLabel) {
            return category.localizedTitle
        }
        return scannerLabel
    }

    public var previewLabels: Set<String> {
        var labels: Set<String> = [localizedTitle, rawValue]

        switch self {
        case .appCaches:
            labels.insert("App caches")
            labels.insert("Selected app caches")
        case .packageManagers:
            labels.insert("Package managers")
            labels.formUnion(["Homebrew cache", "npm cache", "yarn cache", "pnpm store", "CocoaPods cache"])
        case .gradleMaven:
            labels.insert("Gradle + Maven")
            labels.insert("Gradle caches + wrapper + daemon")
        case .flutterDart:
            labels.insert("Flutter / Dart")
            labels.insert("Dart/Flutter package caches")
        case .xcode:
            labels.insert("Xcode")
            labels.insert("Xcode cleanup")
        case .iosSimulators:
            labels.insert("iOS Simulators")
            labels.insert("Simulator caches")
        case .androidCaches:
            labels.insert("Android caches")
            labels.insert("Android build caches")
        case .androidSDK:
            labels.insert("Android SDK")
            labels.insert("Android SDK cleanup")
        case .ideCaches:
            labels.insert("IDE / Electron caches")
        case .browserCaches:
            labels.insert("Browser caches")
        case .messagingMedia:
            labels.insert("Messaging / media")
            labels.insert("Messaging / media caches")
        case .docker:
            labels.insert("Docker")
        case .languageCaches:
            labels.insert("Language caches")
        case .userLogs:
            labels.insert("User logs")
        case .systemCaches:
            labels.insert("System caches")
        case .appContainers:
            labels.insert("App containers")
            labels.insert("App container caches")
        case .dotfileCaches:
            labels.insert("Dotfile caches")
        case .scatteredJunk:
            labels.insert("Scattered junk")
        case .largeFiles:
            labels.insert("Large files")
            labels.insert("Large Files")
        case .dynamicCacheDiscovery:
            labels.formUnion(["Dynamic cache discovery", "Auto-cleanable", "Review manually"])
        case .timeMachineSnapshots:
            labels.insert("Time Machine Snapshots")
        case .iosBackups:
            labels.insert("iOS Backups")
        case .mailDownloads:
            labels.insert("Mail Downloads")
        case .savedAppState:
            labels.insert("Saved Application State")
        case .crashReporter:
            labels.insert("Crash Reporter")
        case .assetsV2:
            labels.insert("AssetsV2 / iWork Templates")
        case .cloudKitCache:
            labels.insert("CloudKit Cache")
        case .swiftPMCache:
            labels.insert("Swift Package Manager Cache")
        case .carthageCache:
            labels.insert("Carthage Cache")
        case .steamCache:
            labels.insert("Steam Cache")
        case .teamsCache:
            labels.insert("Microsoft Teams Cache")
        case .adobeCaches:
            labels.insert("Adobe Caches")
        case .chromeExtraCaches:
            labels.insert("Chrome Extra Caches")
        case .sharedFileLists:
            labels.insert("Shared File Lists")
        case .photosCache:
            labels.insert("Photos Cache")
        case .garminFitbit:
            labels.insert("Garmin / Fitbit")
        case .oldBackups:
            labels.insert("Old Backups")
        case .aiModels:
            labels.insert("AI Models")
        case .installerPackages:
            labels.insert("Installer Packages")
        case .dnsFlush:
            labels.insert("DNS Cache")
        case .fontCache:
            labels.insert("Font Cache")
        case .projectBuildArtifacts:
            labels.insert("Project build artifacts")
            labels.insert("Project-local build artifacts")
        }

        return labels
    }
}

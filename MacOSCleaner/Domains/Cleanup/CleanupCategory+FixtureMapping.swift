import Foundation

extension CleanupCategory {

    public var localizedTitle: String {
        "category.\(rawValue)".localized
    }

    /// Maps scanner/engine group labels to the localized category title used in the preview UI.
    public static func localizedGroupTitle(for scannerLabel: String) -> String {
        for category in CleanupCategory.allCases where category.previewLabels.contains(scannerLabel) {
            return category.localizedTitle
        }
        return scannerLabel
    }

    public var previewLabels: Set<String> {
        var labels: Set<String> = [localizedTitle]

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
        case .orphanedRemnants:
            labels.insert("Orphaned remnants")
        case .orphanedFiles:
            labels.insert("Orphaned files")
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
        case .ideOldVersions:
            labels.insert("Old IDE Versions")
            labels.insert("Old IDE versions")
        case .launchAgents:
            labels.insert("Launch Agents")
        case .launchDaemons:
            labels.insert("Launch Daemons")
        case .privilegedHelpers:
            labels.insert("Privileged Helper Tools")
        case .pkgReceipts:
            labels.insert("Package Receipts")
        case .internetPlugins:
            labels.insert("Internet Plugins")
        case .sharedFileLists:
            labels.insert("Shared File Lists")
        case .cloudDocs:
            labels.insert("Cloud Docs")
        case .photosCache:
            labels.insert("Photos Cache")
        case .voiceMemos:
            labels.insert("Voice Memos")
        case .garageBandLogic:
            labels.insert("GarageBand / Logic Pro")
        case .iMovieFinalCut:
            labels.insert("iMovie / Final Cut")
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
        case .sleepImage:
            labels.insert("Sleep Image")
        case .duplicateFiles:
            labels.insert("Duplicate Files")
        case .unusedApps:
            labels.insert("Unused Apps")
        case .projectBuildArtifacts:
            labels.insert("Project build artifacts")
            labels.insert("Project-local build artifacts")
        }

        return labels
    }

    public static func fromFixturePathType(_ pathType: CleanupPathType) -> [CleanupCategory] {
        switch pathType {
        case .caches:
            return [.appCaches, .browserCaches, .ideCaches, .messagingMedia, .languageCaches, .systemCaches]
        case .applicationSupport:
            return [.ideCaches, .orphanedRemnants, .orphanedFiles]
        case .containers:
            return [.appContainers, .orphanedRemnants]
        case .groupContainers:
            return [.appContainers, .orphanedRemnants]
        case .preferences:
            return [.orphanedRemnants, .savedAppState]
        case .logs:
            return [.userLogs, .crashReporter]
        case .savedState:
            return [.savedAppState]
        case .httpStorages:
            return [.orphanedFiles]
        case .webkit:
            return [.orphanedFiles]
        case .applicationScripts:
            return [.orphanedRemnants]
        case .launchAgents:
            return [.launchAgents]
        case .launchDaemons:
            return [.launchDaemons]
        case .privilegedHelperTools:
            return [.privilegedHelpers]
        case .pkgReceipts:
            return [.pkgReceipts]
        case .internetPlugins:
            return [.internetPlugins]
        case .cookies:
            return [.orphanedFiles]
        case .diagnosticReports:
            return [.crashReporter]
        case .cloudDocs:
            return [.cloudDocs]
        case .sharedFileLists:
            return [.sharedFileLists]
        case .developerArtifacts:
            return []
        }
    }

    public static func fromCleanupJsonScannerId(_ scannerId: String) -> CleanupCategory? {
        switch scannerId {
        case "browser_data_scanner": return .browserCaches
        case "logs_scanner": return .userLogs
        case "language_toolchain_scanner": return .languageCaches
        case "cache_scanner": return .appCaches
        case "xcode_derived_data_scanner": return .xcode
        case "simulator_scanner": return .iosSimulators
        case "quicklook_cache_scanner": return .systemCaches
        case "photo_library_cache_scanner": return .photosCache
        case "voice_memos_scanner": return .voiceMemos
        case "garageband_logic_scanner": return .garageBandLogic
        case "imovie_final_cut_scanner": return .iMovieFinalCut
        case "garmin_fitbit_scanner": return .garminFitbit
        case "old_backups_scanner": return .oldBackups
        case "mail_attachments_scanner": return .mailDownloads
        case "dns_cache_scanner": return .dnsFlush
        case "font_cache_scanner": return .fontCache
        case "sleep_image_scanner": return .sleepImage
        case "duplicate_files_scanner": return .duplicateFiles
        case "unused_apps_scanner": return .unusedApps
        case "docker_scanner": return .docker
        case "downloads_scanner": return .largeFiles
        case "trash_scanner": return .scatteredJunk
        case "time_machine_local_snapshots_scanner": return .timeMachineSnapshots
        case "itunes_backup_scanner": return .iosBackups
        case "spotlight_index_scanner": return .systemCaches
        case "swap_files_scanner": return .systemCaches
        case "project_build_artifacts_scanner": return .projectBuildArtifacts
        default: return nil
        }
    }
}

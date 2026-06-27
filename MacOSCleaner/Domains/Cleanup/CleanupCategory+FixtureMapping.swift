import Foundation

extension CleanupCategory {

    public var localizedTitle: String {
        "category.\(rawValue)".localized
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
        default: return nil
        }
    }
}

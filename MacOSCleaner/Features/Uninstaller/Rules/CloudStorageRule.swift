import Foundation

public struct CloudStorageRule: ApplicationRule {
    public let displayName = "Cloud Storage"
    public let supportedBundleIDs: Set<String> = [
        "com.getdropbox.dropbox",
        "com.google.drivefs",
        "com.microsoft.OneDrive",
        "com.box.desktop",
        "com.pcloud.pcloud.macos",
        "mega.mac",
        "com.nextcloud.desktopclient",
    ]
    public let supportedTeamIDs: Set<String> = []
    public let supportedAppNames: Set<String> = [
        "Dropbox", "Google Drive", "OneDrive", "Box",
        "pCloud", "MEGAsync", "Nextcloud",
    ]

    public init() {}

    public func evidence(for candidate: URL, identity: AppIdentity) -> [ArtifactEvidence] {
        let path = candidate.path.lowercased()
        var evidence: [ArtifactEvidence] = []

        if path.contains("/containers/com.getdropbox.dropbox") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 100))
        }
        if path.contains("/containers/com.dropbox.") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 90))
        }
        if path.contains("/group containers/") && path.contains("com.getdropbox.dropbox") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 90))
        }
        if path.contains("/application scripts/") && path.contains("com.getdropbox.dropbox") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 80))
        }
        if path.contains("/application support/dropbox") {
            evidence.append(ArtifactEvidence(source: .appName, weight: 70))
        }
        if path.contains("/application support/dropboxelectron") {
            evidence.append(ArtifactEvidence(source: .appName, weight: 70))
        }
        if path.hasSuffix("/.dropbox") || path.contains("/.dropbox/") {
            evidence.append(ArtifactEvidence(source: .rule, weight: 60))
        }
        if path.hasSuffix("/dropbox") || path.hasSuffix("/dropbox_debug.log") {
            evidence.append(ArtifactEvidence(source: .rule, weight: 50))
        }
        if path.contains("/dropboxhelper tools") {
            evidence.append(ArtifactEvidence(source: .rule, weight: 70))
        }
        if path.contains("/cloudstorage/dropbox") {
            evidence.append(ArtifactEvidence(source: .rule, weight: 50))
        }

        if path.contains("/application support/google/drive") || path.contains("/application support/google/drivefs") {
            evidence.append(ArtifactEvidence(source: .appName, weight: 70))
        }
        if path.contains("/containers/com.google.drivefs") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 100))
        }
        if path.contains("/group containers/") && path.contains("group.com.google.drivefs") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 90))
        }
        if path.contains("/application scripts/com.google.drivefs") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 80))
        }
        if path.contains("/caches/com.google.drivefs") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 50))
        }

        if path.contains("/application support/onedrive") {
            evidence.append(ArtifactEvidence(source: .appName, weight: 70))
        }
        if path.contains("/containers/com.microsoft.onedrive") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 90))
        }
        if path.contains("/group containers/ubf8t346g9.officeonedrivesyncintegration") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 80))
        }
        if path.hasSuffix("/onedrive") {
            evidence.append(ArtifactEvidence(source: .rule, weight: 50))
        }

        if path.contains("/application support/box") {
            evidence.append(ArtifactEvidence(source: .appName, weight: 70))
        }
        if path.contains("/caches/com.box.desktop") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 50))
        }

        if path.contains("/application support/pcloud") {
            evidence.append(ArtifactEvidence(source: .appName, weight: 70))
        }
        if path.contains("/containers/com.pcloud.pcloud.macos") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 90))
        }
        if path.hasSuffix("/pclouddrive") {
            evidence.append(ArtifactEvidence(source: .rule, weight: 50))
        }

        if path.contains("/application support/mega limited") {
            evidence.append(ArtifactEvidence(source: .appName, weight: 70))
        }
        if path.contains("/containers/mega.mac") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 90))
        }
        if path.hasSuffix("/mega") {
            evidence.append(ArtifactEvidence(source: .rule, weight: 50))
        }

        if path.contains("/application support/nextcloud") {
            evidence.append(ArtifactEvidence(source: .appName, weight: 70))
        }
        if path.contains("/containers/com.nextcloud.desktopclient") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 90))
        }
        if path.hasSuffix("/nextcloud") {
            evidence.append(ArtifactEvidence(source: .rule, weight: 50))
        }

        return evidence
    }
}

import Foundation

public struct CommunicationRule: ApplicationRule {
    public let displayName = "Communication"
    public let supportedBundleIDs: Set<String> = [
        "net.whatsapp.WhatsApp",
        "ru.keepcoder.Telegram",
        "org.signal.Signal",
        "us.zoom.xos",
        "com.skype.skype",
    ]
    public let supportedTeamIDs: Set<String> = []
    public let supportedAppNames: Set<String> = [
        "WhatsApp", "Telegram", "Signal", "Zoom", "Skype",
    ]

    public init() {}

    public func evidence(for candidate: URL, identity: AppIdentity) -> [ArtifactEvidence] {
        let path = candidate.path.lowercased()
        var evidence: [ArtifactEvidence] = []

        if path.contains("/containers/net.whatsapp.whatsapp") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 90))
        }
        if path.contains("/application support/whatsapp") {
            evidence.append(ArtifactEvidence(source: .appName, weight: 70))
        }
        if path.contains("/caches/net.whatsapp.whatsapp") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 50))
        }
        if path.contains("/preferences/net.whatsapp.whatsapp.plist") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 80))
        }

        if path.contains("/application support/telegram") {
            evidence.append(ArtifactEvidence(source: .appName, weight: 70))
        }
        if path.contains("/application support/ru.keepcoder.telegram") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 70))
        }
        if path.contains("/containers/ru.keepcoder.telegram") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 90))
        }
        if path.contains("/group containers/") && path.contains("ru.keepcoder.telegram") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 85))
        }
        if path.contains("/caches/ru.keepcoder.telegram") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 50))
        }

        if path.contains("/application support/signal") {
            evidence.append(ArtifactEvidence(source: .appName, weight: 70))
        }
        if path.contains("/caches/org.signal.signal") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 50))
        }
        if path.contains("/preferences/org.signal.signal.plist") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 80))
        }

        if path.contains("/application support/zoom.us") {
            evidence.append(ArtifactEvidence(source: .appName, weight: 70))
        }
        if path.contains("/application support/zoomupdater") {
            evidence.append(ArtifactEvidence(source: .rule, weight: 70))
        }
        if path.contains("/containers/us.zoom.xos") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 90))
        }
        if path.contains("/caches/us.zoom.xos") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 50))
        }
        if path.contains("/group containers/") && path.contains("zoomclient3rd") {
            evidence.append(ArtifactEvidence(source: .rule, weight: 85))
        }
        if path.contains("/.zoomus") {
            evidence.append(ArtifactEvidence(source: .rule, weight: 60))
        }
        if path.contains("/desktop/zoom") || path.contains("/documents/zoom") {
            evidence.append(ArtifactEvidence(source: .rule, weight: 50))
        }
        if path.contains("/privilegedhelpertools/us.zoom") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 70))
        }
        if path.contains("/audio/plug-ins/hal/zoomaudioddevice.driver") {
            evidence.append(ArtifactEvidence(source: .rule, weight: 70))
        }
        if path.contains("/launchdaemons/") && (path.contains("us.zoom") || path.contains("com.zoom")) {
            evidence.append(ArtifactEvidence(source: .rule, weight: 70))
        }

        if path.contains("/application support/skype") {
            evidence.append(ArtifactEvidence(source: .appName, weight: 70))
        }
        if path.contains("/caches/com.skype.skype") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 50))
        }
        if path.contains("/preferences/com.skype.skype.plist") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 80))
        }

        return evidence
    }
}

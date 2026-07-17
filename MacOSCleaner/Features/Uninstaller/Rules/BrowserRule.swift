import Foundation

public struct BrowserRule: ApplicationRule {
    public let displayName = "Browser"
    public let supportedBundleIDs: Set<String> = [
        "com.google.Chrome",
        "com.google.Chrome.canary",
        "org.chromium.Chromium",
        "com.brave.Browser",
        "com.brave.Browser.beta",
        "com.brave.Browser.nightly",
        "com.microsoft.edgemac",
        "com.microsoft.edgemac.Dev",
        "com.microsoft.edgemac.Beta",
        "com.microsoft.edgemac.Canary",
        "org.mozilla.firefox",
        "org.mozilla.firefoxdeveloperedition",
        "org.mozilla.nightly",
        "company.thebrowser.Browser",
        "com.operasoftware.Opera",
        "com.operasoftware.OperaGX",
        "com.operasoftware.OperaDeveloperEdition",
        "com.vivaldi.Vivaldi",
        "com.kagi.kagimacOS",
        "org.torproject.torbrowser",
        "com.duckduckgo.macos.browser",
        "net.waterfox.waterfox",
        "io.gitlab.librewolf-community",
        "net.mullvad.MullvadBrowser",
        "ru.yandex.desktop.yandex-browser",
    ]
    public let supportedTeamIDs: Set<String> = [
        "EQHXZ8M8AV",  // Google
        "BFYZ25A2P4",  // Brave
        "G7HH3F8CAK",  // Opera?
    ]
    public let supportedAppNames: Set<String> = [
        "Google Chrome", "Chrome", "Chromium", "Brave Browser", "Brave",
        "Microsoft Edge", "Edge", "Firefox", "Firefox Developer Edition", "Firefox Nightly",
        "Arc", "Opera", "Opera GX", "Opera Developer", "Vivaldi",
        "Orion", "Tor Browser", "DuckDuckGo", "Waterfox", "LibreWolf",
        "Mullvad Browser", "Yandex",
    ]

    private let browserArtifactDirs: Set<String> = [
        "Default", "Profile", "Profiles",
        "IndexedDB", "GPUCache", "Code Cache",
        "Service Worker", "CacheStorage",
        "Session Storage", "Local Extension Storage",
        "blob_storage", "File System",
    ]

    public init() {}

    public func evidence(for candidate: URL, identity: AppIdentity) -> [ArtifactEvidence] {
        let path = candidate.path.lowercased()
        let name = candidate.lastPathComponent
        var evidence: [ArtifactEvidence] = []

        if browserArtifactDirs.contains(name) {
            evidence.append(ArtifactEvidence(source: .rule, weight: 40))
        }

        if path.contains("/application support/\(identity.appName.lowercased())") {
            evidence.append(ArtifactEvidence(source: .appName, weight: 60))
        }

        if path.contains("/caches/\(identity.appName.lowercased())") {
            evidence.append(ArtifactEvidence(source: .appName, weight: 50))
        }

        let bid = identity.bundleID.lowercased()
        if bid.contains("google") && bid.contains("chrome") {
            if path.contains("/application support/google/") || path.contains("/caches/google/") || path.contains("/logs/google/") {
                if path.contains("/chrome") || name == "Google" {
                    evidence.append(ArtifactEvidence(source: .rule, weight: 70))
                }
            }
            if path.contains("/caches/com.google.chrome") {
                evidence.append(ArtifactEvidence(source: .bundleID, weight: 80))
            }
        }

        if bid.contains("brave") {
            if path.contains("/bravesoftware/") || path.contains("/caches/com.brave.") {
                evidence.append(ArtifactEvidence(source: .rule, weight: 70))
            }
        }

        if bid.contains("operasoftware") || bid.contains("vivaldi") || bid.contains("edgemac") {
            if path.contains(bid) || path.contains("/\(identity.appName.lowercased())") {
                evidence.append(ArtifactEvidence(source: .bundleID, weight: 70))
            }
        }

        return evidence
    }
}

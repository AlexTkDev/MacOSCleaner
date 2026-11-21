import Foundation

public struct BrowserRule: ApplicationRule {
    public let displayName = "Browser"
    public let supportedBundleIDs: Set<String> = [
        "com.google.Chrome",
        "com.google.Chrome.beta",
        "com.google.Chrome.canary",
        "com.google.Chrome.dev",
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
    // Never match by Team ID: EQHXZ8M8AV is shared across all Google apps (Drive, Earth, Updater, ...).
    public let supportedTeamIDs: Set<String> = []
    public let supportedAppNames: Set<String> = [
        "Google Chrome", "Chrome", "Chromium", "Brave Browser", "Brave",
        "Microsoft Edge", "Edge", "Firefox", "Firefox Developer Edition", "Firefox Nightly",
        "Arc", "Opera", "Opera GX", "Opera Developer", "Vivaldi",
        "Orion", "Tor Browser", "DuckDuckGo", "Waterfox", "LibreWolf",
        "Mullvad Browser", "Yandex",
    ]

    public static let knownLowercasedBundleIDs: Set<String> = Set(
        BrowserRule().supportedBundleIDs.map { $0.lowercased() }
    )

    /// True for Chromium/browser web-app shortcuts (`com.google.Chrome.app.<id>`, etc.).
    public static func isBrowserPWAShimBundleID(_ bundleID: String) -> Bool {
        let lower = bundleID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard let range = lower.range(of: ".app.") else { return false }
        let hostPrefix = String(lower[..<range.lowerBound])
        return knownLowercasedBundleIDs.contains(hostPrefix)
    }

    public static func isKnownBrowserBundleID(_ bundleID: String) -> Bool {
        let lower = bundleID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lower.isEmpty, !lower.hasPrefix("unknown."), !isBrowserPWAShimBundleID(lower) else {
            return false
        }
        return knownLowercasedBundleIDs.contains(lower)
    }

    /// Product-relative vendor roots (`Library/Application Support/...`, `Library/Caches/...`) owned by each browser channel.
    public static func vendorRoots(forBundleID bundleID: String) -> [(vendor: String, product: String?)] {
        let bid = bundleID.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard isKnownBrowserBundleID(bid) else { return [] }
        switch bid {
        case "com.google.chrome":
            return [("Google", "Chrome")]
        case "com.google.chrome.beta":
            return [("Google", "Chrome Beta")]
        case "com.google.chrome.canary":
            return [("Google", "Chrome Canary")]
        case "com.google.chrome.dev":
            return [("Google", "Chrome Dev")]
        case "org.chromium.chromium":
            return [("Chromium", nil)]
        case "com.brave.browser":
            return [("BraveSoftware", "Brave-Browser")]
        case "com.brave.browser.beta":
            return [("BraveSoftware", "Brave-Browser-Beta")]
        case "com.brave.browser.nightly":
            return [("BraveSoftware", "Brave-Browser-Nightly")]
        case "com.microsoft.edgemac":
            return [("Microsoft Edge", nil)]
        case "com.microsoft.edgemac.beta":
            return [("Microsoft Edge Beta", nil)]
        case "com.microsoft.edgemac.canary":
            return [("Microsoft Edge Canary", nil)]
        case "com.microsoft.edgemac.dev":
            return [("Microsoft Edge Dev", nil)]
        case "org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition", "org.mozilla.nightly":
            return [("Mozilla", nil), ("Firefox", nil)]
        case "com.operasoftware.opera":
            return [("com.operasoftware.Opera", nil), ("Opera Software", "Opera Stable"), ("Opera", nil)]
        case "com.operasoftware.operagx":
            return [("com.operasoftware.OperaGX", nil), ("Opera Software", "Opera GX Stable")]
        case "com.operasoftware.operadeveloperedition":
            return [("com.operasoftware.OperaDeveloperEdition", nil), ("Opera Software", "Opera Developer")]
        case "com.vivaldi.vivaldi":
            return [("Vivaldi", nil)]
        case "company.thebrowser.browser":
            return [("Arc", nil)]
        case "com.kagi.kagimacos":
            return [("Orion", nil)]
        case "org.torproject.torbrowser":
            return [("TorBrowser-Data", nil)]
        case "com.duckduckgo.macos.browser":
            return [("DuckDuckGo", nil)]
        case "net.waterfox.waterfox":
            return [("Waterfox", nil)]
        case "io.gitlab.librewolf-community":
            return [("LibreWolf", nil)]
        case "net.mullvad.mullvadbrowser":
            return [("MullvadBrowser", nil)]
        case "ru.yandex.desktop.yandex-browser":
            return [("Yandex", "YandexBrowser")]
        default:
            return []
        }
    }

    private let browserArtifactDirs: Set<String> = [
        "Default", "Profile", "Profiles",
        "IndexedDB", "GPUCache", "Code Cache",
        "Service Worker", "CacheStorage",
        "Session Storage", "Local Extension Storage",
        "blob_storage", "File System",
    ]

    public init() {}

    public func matches(identity: AppIdentity) -> Bool {
        Self.isKnownBrowserBundleID(identity.bundleID)
    }

    public func evidence(for candidate: URL, identity: AppIdentity) -> [ArtifactEvidence] {
        guard matches(identity: identity) else { return [] }

        let path = candidate.path.lowercased()
        let name = candidate.lastPathComponent
        let bid = identity.bundleID.lowercased()
        var evidence: [ArtifactEvidence] = []

        let ownedMarkers = Self.ownedPathMarkers(forBundleID: bid, appName: identity.appName)
        let belongsToThisBrowser = ownedMarkers.contains { marker in
            path.contains("/\(marker)/") || path.hasSuffix("/\(marker)")
        }

        if browserArtifactDirs.contains(name), belongsToThisBrowser {
            evidence.append(ArtifactEvidence(source: .rule, weight: 40))
        }

        if path.contains("/application support/\(identity.appName.lowercased())") {
            evidence.append(ArtifactEvidence(source: .appName, weight: 60))
        }

        if path.contains("/caches/\(identity.appName.lowercased())") {
            evidence.append(ArtifactEvidence(source: .appName, weight: 50))
        }

        for (vendor, product) in Self.vendorRoots(forBundleID: bid) {
            let marker = product.map { "\(vendor)/\($0)".lowercased() } ?? vendor.lowercased()
            let appSupportMarker = "/application support/\(marker)"
            let cachesMarker = "/caches/\(marker)"
            let logsMarker = "/logs/\(marker)"
            if path.contains(appSupportMarker + "/") || path.hasSuffix(appSupportMarker)
                || path.contains(cachesMarker + "/") || path.hasSuffix(cachesMarker)
                || path.contains(logsMarker + "/") || path.hasSuffix(logsMarker) {
                evidence.append(ArtifactEvidence(source: .rule, weight: 70))
                break
            }
        }

        if path.contains("/caches/\(bid)/") || path.hasSuffix("/caches/\(bid)") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 80))
        }

        return evidence
    }

    private static func ownedPathMarkers(forBundleID bid: String, appName: String) -> [String] {
        var markers: [String] = [bid, appName.lowercased()].filter { !$0.isEmpty }
        for (vendor, product) in vendorRoots(forBundleID: bid) {
            if let product {
                markers.append("\(vendor)/\(product)".lowercased())
            } else {
                markers.append(vendor.lowercased())
            }
        }
        return markers
    }
}

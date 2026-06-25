import Foundation

public struct TerminalRule: ApplicationRule {
    public let displayName = "Terminal"
    public let supportedBundleIDs: Set<String> = [
        "com.googlecode.iterm2",
        "dev.warp.Warp-Stable",
        "org.tabby",
        "co.zeit.hyper",
        "org.alacritty",
        "com.github.wez.wezterm",
        "net.kovidgoyal.kitty",
    ]
    public let supportedTeamIDs: Set<String> = []
    public let supportedAppNames: Set<String> = [
        "iTerm2", "Warp", "Tabby", "Hyper", "Alacritty", "WezTerm", "Kitty",
    ]

    public init() {}

    public func evidence(for candidate: URL, identity: AppIdentity) -> [ArtifactEvidence] {
        let path = candidate.path.lowercased()
        var evidence: [ArtifactEvidence] = []

        if path.contains("/preferences/com.googlecode.iterm2.plist") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 80))
        }
        if path.contains("/application support/iterm2") {
            evidence.append(ArtifactEvidence(source: .appName, weight: 70))
        }
        if path.contains("/caches/com.googlecode.iterm2") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 50))
        }
        if path.contains("/saved application state/com.googlecode.iterm2") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 60))
        }
        if path.contains("/.iterm2") {
            evidence.append(ArtifactEvidence(source: .rule, weight: 60))
        }

        if path.contains("/application support/dev.warp.warp-stable") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 70))
        }
        if path.contains("/application support/warp") {
            evidence.append(ArtifactEvidence(source: .appName, weight: 70))
        }
        if path.contains("/caches/dev.warp.warp-stable") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 50))
        }
        if path.contains("/preferences/dev.warp.warp-stable.plist") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 80))
        }
        if path.contains("/.warp") {
            evidence.append(ArtifactEvidence(source: .rule, weight: 60))
        }

        if path.contains("/application support/tabby") {
            evidence.append(ArtifactEvidence(source: .appName, weight: 70))
        }
        if path.contains("/caches/org.tabby") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 50))
        }
        if path.contains("/preferences/org.tabby.plist") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 80))
        }

        if path.contains("/application support/hyper") {
            evidence.append(ArtifactEvidence(source: .appName, weight: 70))
        }
        if path.contains("/caches/co.zeit.hyper") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 50))
        }
        if path.contains("/.hyper.js") || path.contains("/.hyper_plugins") {
            evidence.append(ArtifactEvidence(source: .rule, weight: 60))
        }

        if path.contains("/.config/alacritty") {
            evidence.append(ArtifactEvidence(source: .rule, weight: 60))
        }
        if path.contains("/preferences/org.alacritty.plist") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 80))
        }

        if path.contains("/.config/wezterm") {
            evidence.append(ArtifactEvidence(source: .rule, weight: 60))
        }
        if path.contains("/.wezterm.lua") {
            evidence.append(ArtifactEvidence(source: .rule, weight: 60))
        }
        if path.contains("/preferences/com.github.wez.wezterm.plist") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 80))
        }

        if path.contains("/.config/kitty") {
            evidence.append(ArtifactEvidence(source: .rule, weight: 60))
        }
        if path.contains("/.cache/kitty") {
            evidence.append(ArtifactEvidence(source: .rule, weight: 50))
        }
        if path.contains("/preferences/net.kovidgoyal.kitty.plist") {
            evidence.append(ArtifactEvidence(source: .bundleID, weight: 80))
        }

        return evidence
    }
}

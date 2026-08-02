import Foundation

public enum ParentLinker {
    public static func link(
        url: URL,
        identity: AppIdentity,
        homeDirectory: String = NSHomeDirectory()
    ) -> [(parent: URL, via: Evidence)] {
        var links: [(URL, Evidence)] = []
        let path = url.standardizedFileURL.path
        let bundlePath = identity.bundleURL.standardizedFileURL.path
        let home = homeDirectory

        guard path.hasPrefix(home + "/Library") || path.hasPrefix("/Library") || path.hasPrefix("/private/var/folders") else {
            return links
        }

        let pathComponents = (path as NSString).pathComponents

        for i in 0..<pathComponents.count {
            let component = pathComponents[i]

            if identity.vendorNames.contains(component) || component == identity.appName {
                let parentPath = Array(pathComponents[0...i]).joined(separator: "/")
                let parentURL = NormalizedPath.url(parentPath)
                links.append((parentURL, .vendorName))
            }

            if component == identity.bundleID {
                let parentPath = Array(pathComponents[0...i]).joined(separator: "/")
                let parentURL = NormalizedPath.url(parentPath)
                links.append((parentURL, .bundleIDExact))
            }

            if component.hasPrefix(identity.bundleID + ".") {
                let parentPath = Array(pathComponents[0...i]).joined(separator: "/")
                let parentURL = NormalizedPath.url(parentPath)
                links.append((parentURL, .bundleIDPrefix))
            }

            if identity.appGroups.contains(component) {
                let parentPath = Array(pathComponents[0...i]).joined(separator: "/")
                links.append((NormalizedPath.url(parentPath), .appGroup))
            } else if let teamID = identity.teamID, component.hasPrefix(teamID + ".") {
                let suffix = String(component.dropFirst(teamID.count + 1)).lowercased()
                if suffix == identity.bundleID.lowercased() || EvidenceProbe.bundleIDSuffixMatch(suffix, bundleID: identity.bundleID.lowercased()) {
                    let parentPath = Array(pathComponents[0...i]).joined(separator: "/")
                    links.append((NormalizedPath.url(parentPath), .appGroup))
                }
            }
        }

        if path.hasPrefix(bundlePath + "/") || path == bundlePath {
            links.append((identity.bundleURL, .bundleIDExact))
        }

        return links
    }
}

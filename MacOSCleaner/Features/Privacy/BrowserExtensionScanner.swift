import AppKit
import Foundation
import OSLog

private extension Logger {
    static let extensions = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "input.MacOSCleaner",
        category: "BrowserExtensionScanner"
    )
}

public struct BrowserExtensionLaunchPlan: Sendable, Equatable {
    public let browserBundleID: String
    public let arguments: [String]
    public let fallbackURLString: String?
    public let requiresNewInstance: Bool
    public let instructionKey: String
}

public actor BrowserExtensionScanner {
    private let commandRunner: any CommandRunning
    private let fileManager: FileManager
    private let homeDirectory: String

    public init(
        commandRunner: any CommandRunning = CommandRunner(),
        fileManager: FileManager = .default,
        homeDirectory: String = NSHomeDirectory()
    ) {
        self.commandRunner = commandRunner
        self.fileManager = fileManager
        self.homeDirectory = homeDirectory
    }

    public func scanAll() async -> [BrowserExtensionItem] {
        async let safari = scanSafari()
        let chromium = scanAllChromium()
        let firefox = scanFirefox()
        let combined = await safari + chromium + firefox

        return combined.sorted { lhs, rhs in
            if lhs.risk != rhs.risk {
                return lhs.risk > rhs.risk
            }
            if lhs.browser != rhs.browser {
                return lhs.browser.displayName < rhs.browser.displayName
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    // MARK: - Safari (pluginkit + .appex fallback)

    func scanSafari() async -> [BrowserExtensionItem] {
        var found: [String: BrowserExtensionItem] = [:]

        // 1. pluginkit query
        for point in ["com.apple.Safari.web-extension", "com.apple.Safari.extension"] {
            if let result = try? await commandRunner.run(
                command: "/usr/bin/pluginkit",
                arguments: ["-m", "-v", "-A", "-D", "-p", point],
                timeout: .seconds(5)
            ), result.exitCode == 0 {
                let parsed = Self.parsePluginkitOutput(result.stdout, fileManager: fileManager)
                for item in parsed {
                    found[item.extensionID] = item
                }
            }
        }

        // 2. Fallback / enrichment from discovered .app bundles' Contents/PlugIns/*.appex
        let appDirs = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: homeDirectory + "/Applications", isDirectory: true),
        ]
        for dir in appDirs {
            for appURL in AppDiscovery.applicationBundles(in: dir, fileManager: fileManager) {
                let plugInsURL = appURL.appendingPathComponent("Contents/PlugIns", isDirectory: true)
                guard let plugIns = try? fileManager.contentsOfDirectory(
                    at: plugInsURL,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                ) else { continue }
                for appexURL in plugIns where appexURL.pathExtension.lowercased() == "appex" {
                    if let item = Self.parseSafariAppex(at: appexURL, parentAppURL: appURL, isEnabled: nil) {
                        if found[item.extensionID] == nil {
                            found[item.extensionID] = item
                        }
                    }
                }
            }
        }

        return Array(found.values)
    }

    static func parsePluginkitOutput(_ output: String, fileManager: FileManager = .default) -> [BrowserExtensionItem] {
        var items: [BrowserExtensionItem] = []
        // Verbose pluginkit outputs blocks separated by blank lines or lines starting with +, -, space, or bundle id.
        var currentPath: String?
        var currentEnabled: Bool?

        func flush() {
            guard let path = currentPath else { return }
            let url = URL(fileURLWithPath: path)
            let parentApp = NetworkSnapshotService.enclosingAppBundleURL(fromExecutablePath: path)
            if let item = parseSafariAppex(at: url, parentAppURL: parentApp, isEnabled: currentEnabled) {
                items.append(item)
            }
            currentPath = nil
            currentEnabled = nil
        }

        for rawLine in output.components(separatedBy: .newlines) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                flush()
                continue
            }
            if trimmed.hasPrefix("+ ") || trimmed.hasPrefix("- ") || trimmed.hasPrefix("! ") {
                flush()
                currentEnabled = trimmed.hasPrefix("+ ")
                continue
            }
            if trimmed.hasPrefix("Path = ") {
                currentPath = String(trimmed.dropFirst("Path = ".count)).trimmingCharacters(in: .whitespaces)
            } else if currentPath == nil, trimmed.contains(".appex") {
                if let range = trimmed.range(of: "/") {
                    let candidate = String(trimmed[range.lowerBound...]).trimmingCharacters(in: .whitespaces)
                    if fileManager.fileExists(atPath: candidate) {
                        currentPath = candidate
                    }
                }
            }
        }
        flush()
        return items
    }

    static func parseSafariAppex(at appexURL: URL, parentAppURL: URL?, isEnabled: Bool?) -> BrowserExtensionItem? {
        let infoPlistURL = appexURL.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: infoPlistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let nsExt = plist["NSExtension"] as? [String: Any],
              let point = nsExt["NSExtensionPointIdentifier"] as? String,
              point == "com.apple.Safari.web-extension" || point == "com.apple.Safari.extension" else {
            return nil
        }

        let bundleID = plist["CFBundleIdentifier"] as? String ?? appexURL.deletingPathExtension().lastPathComponent
        let name = (plist["CFBundleDisplayName"] as? String)
            ?? (plist["CFBundleName"] as? String)
            ?? appexURL.deletingPathExtension().lastPathComponent
        let version = plist["CFBundleShortVersionString"] as? String ?? "1.0"

        var permissions: [String] = []
        var hostPermissions: [String] = []
        if let websiteAccess = nsExt["SFSafariWebsiteAccess"] as? [String: Any] {
            if let level = websiteAccess["Level"] as? String {
                permissions.append("Website Access: \(level)")
                if level == "All" {
                    hostPermissions.append("<all_urls>")
                }
            }
            if let allowed = websiteAccess["Allowed Domains"] as? [String] {
                hostPermissions.append(contentsOf: allowed)
            }
        }

        let (highRisk, risk) = classifyPermissions(permissions, hostPermissions: hostPermissions)
        let isSystem = appexURL.path.hasPrefix("/System/")

        return BrowserExtensionItem(
            id: "safari|\(bundleID)",
            extensionID: bundleID,
            name: name,
            version: version,
            browser: .safari,
            profileName: nil,
            isEnabled: isEnabled,
            source: isSystem ? .system : .store,
            permissions: permissions,
            hostPermissions: hostPermissions,
            highRiskPermissions: highRisk,
            risk: risk,
            bundleOrManifestURL: appexURL,
            parentAppURL: parentAppURL
        )
    }

    // MARK: - Chromium (Chrome, Edge, Brave, Arc)

    func scanAllChromium() -> [BrowserExtensionItem] {
        let roots: [(browser: ExtensionBrowser, path: String)] = [
            (.chrome, homeDirectory + "/Library/Application Support/Google/Chrome"),
            (.edge, homeDirectory + "/Library/Application Support/Microsoft Edge"),
            (.brave, homeDirectory + "/Library/Application Support/BraveSoftware/Brave-Browser"),
            (.arc, homeDirectory + "/Library/Application Support/Arc/User Data"),
        ]

        var items: [BrowserExtensionItem] = []
        for entry in roots {
            items.append(contentsOf: Self.scanChromiumDirectory(
                userDataDir: URL(fileURLWithPath: entry.path, isDirectory: true),
                browser: entry.browser,
                fileManager: fileManager
            ))
        }
        return items
    }

    static func scanChromiumDirectory(
        userDataDir: URL,
        browser: ExtensionBrowser,
        fileManager: FileManager = .default
    ) -> [BrowserExtensionItem] {
        guard fileManager.fileExists(atPath: userDataDir.path),
              let subdirs = try? fileManager.contentsOfDirectory(
                  at: userDataDir,
                  includingPropertiesForKeys: [.isDirectoryKey],
                  options: [.skipsHiddenFiles]
              ) else {
            return []
        }

        let profileDirs = subdirs.filter { dir in
            let name = dir.lastPathComponent
            return name == "Default" || name.hasPrefix("Profile ")
        }

        var items: [BrowserExtensionItem] = []
        for profileDir in profileDirs {
            let profileName = profileDir.lastPathComponent
            let disabledIDs = readDisabledChromiumExtensionIDs(in: profileDir)
            let extensionsDir = profileDir.appendingPathComponent("Extensions", isDirectory: true)
            guard let extDirs = try? fileManager.contentsOfDirectory(
                at: extensionsDir,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for extDir in extDirs {
                let extID = extDir.lastPathComponent
                guard !extID.hasPrefix(".") else { continue }
                guard let versions = try? fileManager.contentsOfDirectory(
                    at: extDir,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles]
                ) else { continue }

                guard let versionDir = versions.sorted(by: { $0.lastPathComponent > $1.lastPathComponent }).first else {
                    continue
                }
                let manifestURL = versionDir.appendingPathComponent("manifest.json")
                if let item = parseChromiumManifest(
                    at: manifestURL,
                    extensionRootDir: versionDir,
                    extensionID: extID,
                    browser: browser,
                    profileName: profileName,
                    isEnabled: disabledIDs.map { !$0.contains(extID) }
                ) {
                    items.append(item)
                }
            }
        }
        return items
    }

    static func parseChromiumManifest(
        at manifestURL: URL,
        extensionRootDir: URL,
        extensionID: String,
        browser: ExtensionBrowser,
        profileName: String,
        isEnabled: Bool?
    ) -> BrowserExtensionItem? {
        guard let data = try? Data(contentsOf: manifestURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let rawName = json["name"] as? String ?? extensionID
        let name = resolveLocalizedManifestName(rawName, extensionRootDir: extensionRootDir)
        let version = json["version"] as? String ?? "0.0"

        var permissions: [String] = []
        var hostPermissions: [String] = []

        for perm in (json["permissions"] as? [String] ?? []) {
            if perm.contains("://") || perm == "<all_urls>" {
                hostPermissions.append(perm)
            } else {
                permissions.append(perm)
            }
        }
        if let hosts = json["host_permissions"] as? [String] {
            hostPermissions.append(contentsOf: hosts)
        }

        let updateURL = (json["update_url"] as? String ?? "").lowercased()
        let source: ExtensionSource
        if updateURL.contains("clients2.google.com") || updateURL.contains("edge.microsoft.com") {
            source = .store
        } else {
            source = .sideload
        }

        let (highRisk, risk) = classifyPermissions(permissions, hostPermissions: hostPermissions)

        return BrowserExtensionItem(
            id: "\(browser.rawValue)|\(profileName)|\(extensionID)",
            extensionID: extensionID,
            name: name,
            version: version,
            browser: browser,
            profileName: profileName,
            isEnabled: isEnabled,
            source: source,
            permissions: permissions,
            hostPermissions: hostPermissions,
            highRiskPermissions: highRisk,
            risk: risk,
            bundleOrManifestURL: manifestURL,
            parentAppURL: nil
        )
    }

    private static func resolveLocalizedManifestName(_ rawName: String, extensionRootDir: URL) -> String {
        guard rawName.hasPrefix("__MSG_"), rawName.hasSuffix("__") else {
            return rawName
        }
        let key = String(rawName.dropFirst(6).dropLast(2))
        let candidates = ["en", "en_US", "ru"]
        for locale in candidates {
            let msgURL = extensionRootDir
                .appendingPathComponent("_locales/\(locale)/messages.json")
            if let data = try? Data(contentsOf: msgURL),
               let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let entry = dict[key] as? [String: Any],
               let message = entry["message"] as? String,
               !message.isEmpty {
                return message
            }
        }
        return rawName
    }

    private static func readDisabledChromiumExtensionIDs(in profileDir: URL) -> Set<String>? {
        let prefsURL = profileDir.appendingPathComponent("Preferences")
        guard let data = try? Data(contentsOf: prefsURL),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let extensions = json["extensions"] as? [String: Any],
              let settings = extensions["settings"] as? [String: Any] else {
            return nil
        }
        var disabled = Set<String>()
        for (extID, rawEntry) in settings {
            if let entry = rawEntry as? [String: Any],
               let state = entry["state"] as? Int,
               state == 0 {
                disabled.insert(extID)
            }
        }
        return disabled
    }

    // MARK: - Firefox

    func scanFirefox() -> [BrowserExtensionItem] {
        let profilesRoot = URL(fileURLWithPath: homeDirectory + "/Library/Application Support/Firefox/Profiles", isDirectory: true)
        return Self.scanFirefoxProfiles(at: profilesRoot, fileManager: fileManager)
    }

    static func scanFirefoxProfiles(at profilesRoot: URL, fileManager: FileManager = .default) -> [BrowserExtensionItem] {
        guard fileManager.fileExists(atPath: profilesRoot.path),
              let profiles = try? fileManager.contentsOfDirectory(
                  at: profilesRoot,
                  includingPropertiesForKeys: [.isDirectoryKey],
                  options: [.skipsHiddenFiles]
              ) else {
            return []
        }

        var items: [BrowserExtensionItem] = []
        for profileDir in profiles {
            let extJSON = profileDir.appendingPathComponent("extensions.json")
            items.append(contentsOf: parseFirefoxExtensionsJSON(at: extJSON, profileName: profileDir.lastPathComponent))
        }
        return items
    }

    static func parseFirefoxExtensionsJSON(at url: URL, profileName: String) -> [BrowserExtensionItem] {
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let addons = json["addons"] as? [[String: Any]] else {
            return []
        }

        var items: [BrowserExtensionItem] = []
        for addon in addons {
            let type = addon["type"] as? String ?? "extension"
            guard type == "extension" else { continue }
            let location = addon["location"] as? String ?? ""
            if location == "app-builtin" || location == "app-system-defaults" { continue }

            guard let extID = addon["id"] as? String, !extID.isEmpty else { continue }
            let defaultLocale = addon["defaultLocale"] as? [String: Any]
            let name = defaultLocale?["name"] as? String ?? extID
            let version = addon["version"] as? String ?? "0.0"
            let isEnabled = addon["active"] as? Bool
            let sourceURI = (addon["sourceURI"] as? String ?? "").lowercased()

            let source: ExtensionSource
            if sourceURI.contains("addons.mozilla.org") {
                source = .store
            } else if location == "app-profile" && !sourceURI.isEmpty {
                source = .sideload
            } else if location.contains("system") {
                source = .system
            } else {
                source = .sideload
            }

            let userPerms = addon["userPermissions"] as? [String: Any]
            let permissions = userPerms?["permissions"] as? [String] ?? []
            let origins = userPerms?["origins"] as? [String] ?? []
            let (highRisk, risk) = classifyPermissions(permissions, hostPermissions: origins)

            items.append(BrowserExtensionItem(
                id: "firefox|\(profileName)|\(extID)",
                extensionID: extID,
                name: name,
                version: version,
                browser: .firefox,
                profileName: profileName,
                isEnabled: isEnabled,
                source: source,
                permissions: permissions,
                hostPermissions: origins,
                highRiskPermissions: highRisk,
                risk: risk,
                bundleOrManifestURL: url,
                parentAppURL: nil
            ))
        }
        return items
    }

    // MARK: - Risk Classification

    private static let highRiskTokens: Set<String> = [
        "<all_urls>", "*://*/*", "http://*/*", "https://*/*",
        "cookies", "webrequest", "webrequestblocking", "nativemessaging",
        "debugger", "proxy", "clipboardread", "management", "downloads"
    ]

    private static let elevatedRiskTokens: Set<String> = [
        "tabs", "history", "bookmarks", "webnavigation", "declarativerequest",
        "declarativenetrequest", "topsites"
    ]

    public static func classifyPermissions(
        _ permissions: [String],
        hostPermissions: [String]
    ) -> (highRisk: [String], risk: ExtensionPermissionRisk) {
        let all = permissions + hostPermissions
        var flaggedHigh: [String] = []
        var hasElevated = false

        for item in all {
            let lower = item.lowercased()
            if highRiskTokens.contains(lower) || lower.contains("<all_urls>") || lower.hasPrefix("*://*/*") {
                flaggedHigh.append(item)
            } else if elevatedRiskTokens.contains(lower) || lower.contains("://*.") {
                hasElevated = true
            }
        }

        if !flaggedHigh.isEmpty {
            return (flaggedHigh, .high)
        }
        if hasElevated || !hostPermissions.isEmpty {
            return ([], .elevated)
        }
        return ([], .normal)
    }

    // MARK: - Launch Plan & Browser Opener

    public static func launchPlan(for item: BrowserExtensionItem) -> BrowserExtensionLaunchPlan {
        switch item.browser {
        case .chrome, .edge, .brave, .arc:
            let scheme = item.browser.chromiumScheme ?? "chrome"
            let targetURL = "\(scheme)://extensions/?id=\(item.extensionID)"
            var args: [String] = []
            if let profile = item.profileName, !profile.isEmpty {
                args.append("--profile-directory=\(profile)")
            }
            args.append(targetURL)
            return BrowserExtensionLaunchPlan(
                browserBundleID: item.browser.bundleID,
                arguments: args,
                fallbackURLString: targetURL,
                requiresNewInstance: true,
                instructionKey: "privacy_ext_open_chromium_hint"
            )
        case .firefox:
            return BrowserExtensionLaunchPlan(
                browserBundleID: item.browser.bundleID,
                arguments: ["about:addons"],
                fallbackURLString: "about:addons",
                requiresNewInstance: false,
                instructionKey: "privacy_ext_open_firefox_hint"
            )
        case .safari:
            return BrowserExtensionLaunchPlan(
                browserBundleID: item.browser.bundleID,
                arguments: [],
                fallbackURLString: nil,
                requiresNewInstance: false,
                instructionKey: "privacy_ext_open_safari_hint"
            )
        }
    }

    @MainActor
    public static func openInBrowser(_ item: BrowserExtensionItem) async -> String? {
        let plan = launchPlan(for: item)
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: plan.browserBundleID) else {
            if let fallback = plan.fallbackURLString {
                copyToPasteboard(fallback)
            }
            return String(format: "privacy_ext_browser_not_found".localized, item.browser.displayName)
        }

        if item.browser == .safari {
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            _ = try? await NSWorkspace.shared.openApplication(at: appURL, configuration: config)
            return String(format: plan.instructionKey.localized, item.name)
        }

        if item.browser == .firefox {
            let isRunning = NSWorkspace.shared.runningApplications.contains {
                $0.bundleIdentifier == plan.browserBundleID
            }
            if !isRunning {
                let config = NSWorkspace.OpenConfiguration()
                config.activates = true
                config.arguments = plan.arguments
                if (try? await NSWorkspace.shared.openApplication(at: appURL, configuration: config)) != nil {
                    return String(format: plan.instructionKey.localized, item.name)
                }
            } else if let url = URL(string: "about:addons") {
                let config = NSWorkspace.OpenConfiguration()
                config.activates = true
                if (try? await NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: config)) != nil {
                    return String(format: plan.instructionKey.localized, item.name)
                }
            }
            // Fallback: activate Firefox and copy about:addons for quick paste.
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            _ = try? await NSWorkspace.shared.openApplication(at: appURL, configuration: config)
            copyToPasteboard("about:addons")
            return String(format: plan.instructionKey.localized, item.name)
        }

        // Chromium browsers: new instance hand-off passes --profile-directory and internal URL via IPC.
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        config.createsNewApplicationInstance = plan.requiresNewInstance
        config.arguments = plan.arguments
        do {
            _ = try await NSWorkspace.shared.openApplication(at: appURL, configuration: config)
            return nil
        } catch {
            if let fallback = plan.fallbackURLString {
                copyToPasteboard(fallback)
            }
            return String(format: plan.instructionKey.localized, item.name)
        }
    }

    @MainActor
    private static func copyToPasteboard(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}

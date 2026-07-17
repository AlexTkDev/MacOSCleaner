import Foundation

/// Curated residual locations for apps known to break uninstallers.
/// Source of truth: this file (one-shot extracted from the problematic-apps
/// fixture base, hand-maintained onward). Paths use `~` for the user home and
/// may contain `*` globs in individual components.
///
/// Never lists shared components (Google Keystone, Microsoft AutoUpdate,
/// Edge Updater), shared developer toolchains (~/.gradle, Android SDK) or
/// SIP-protected system apps (Safari).
public enum KnownResidualCatalog {

    public struct Entry: Sendable {
        public let name: String
        /// Lowercased exact bundle identifiers.
        public let bundleIDs: Set<String>
        /// Lowercased bundle-ID family prefixes with a trailing dot (com.jetbrains.).
        public let bundleIDPrefixes: [String]
        public let pathTemplates: [String]
    }

    /// Templates whose entry matches the identity's bundle ID; empty when unknown.
    public static func pathTemplates(for identity: AppIdentity) -> [String] {
        pathTemplates(bundleID: identity.bundleID)
    }

    public static func pathTemplates(bundleID: String) -> [String] {
        let bid = bundleID.lowercased()
        guard !bid.isEmpty, !bid.hasPrefix("unknown.") else { return [] }
        var templates: [String] = []
        for entry in entries where entry.bundleIDs.contains(bid)
            || entry.bundleIDPrefixes.contains(where: { bid.hasPrefix($0) }) {
            templates.append(contentsOf: entry.pathTemplates)
        }
        return templates
    }

    /// Expands a template: `~` -> home, `*`/`?` glob components via directory listing.
    /// Returns only existing paths.
    public static func expand(template: String, home: String, fileManager: FileManager = .default) -> [String] {
        CleanupPathExpander.expand(template, home: home, fileManager: fileManager)
    }

    public static let entries: [Entry] = [
        // MARK: 1Password (developer tool for many)
        Entry(
            name: "1Password (developer tool for many)",
            bundleIDs: ["com.1password.1password"],
            bundleIDPrefixes: [],
            pathTemplates: [
                "~/.config/op",
                "~/.op",
                "~/Library/Caches/com.1password.1password",
                "~/Library/Containers/com.1password.1password",
                "~/Library/Group Containers/2BUA8C4S2C.com.agilebits",
                "~/Library/Preferences/com.1password.1password-helper.plist",
                "~/Library/Preferences/com.1password.1password.plist",
            ]
        ),
        // MARK: Alacritty
        Entry(
            name: "Alacritty",
            bundleIDs: ["org.alacritty"],
            bundleIDPrefixes: [],
            pathTemplates: [
                "~/.config/alacritty",
                "~/Library/Preferences/org.alacritty.plist",
            ]
        ),
        // MARK: Alfred (developer-focused launcher)
        Entry(
            name: "Alfred (developer-focused launcher)",
            bundleIDs: ["com.runningwithcrayons.alfred-preferences"],
            bundleIDPrefixes: [],
            pathTemplates: [
                "~/Library/Application Support/Alfred",
                "~/Library/Caches/com.runningwithcrayons.Alfred",
                "~/Library/Preferences/com.runningwithcrayons.Alfred-Preferences.plist",
                "~/Library/Preferences/com.runningwithcrayons.Alfred.plist",
            ]
        ),
        // MARK: Android Studio
        Entry(
            name: "Android Studio",
            bundleIDs: ["com.google.android.studio"],
            bundleIDPrefixes: [],
            pathTemplates: [
                "~/Library/Application Support/AndroidStudio*",
                "~/Library/Application Support/Google/AndroidStudio*",
                "~/Library/Caches/AndroidStudio*",
                "~/Library/Caches/Google/AndroidStudio*",
                "~/Library/Caches/JetBrains/AndroidStudio*",
                "~/Library/HTTPStorages/com.google.android.studio",
                "~/Library/Logs/AndroidStudio*",
                "~/Library/Logs/Google/AndroidStudio*",
                "~/Library/Preferences/AndroidStudio*",
                "~/Library/Preferences/com.android.*",
                "~/Library/Preferences/com.google.android.studio.plist",
                "~/Library/Saved Application State/com.google.android.studio.savedState",
            ]
        ),
        // MARK: Araxis Merge
        Entry(
            name: "Araxis Merge",
            bundleIDs: ["com.araxis.merge"],
            bundleIDPrefixes: [],
            pathTemplates: [
                "~/Library/Application Support/Araxis Merge",
                "~/Library/Preferences/com.araxis.merge.plist",
            ]
        ),
        // MARK: Arc Browser
        Entry(
            name: "Arc Browser",
            bundleIDs: ["company.thebrowser.browser"],
            bundleIDPrefixes: [],
            pathTemplates: [
                "~/Library/Application Support/Arc",
                "~/Library/Caches/Arc",
                "~/Library/Caches/company.thebrowser.Browser",
                "~/Library/HTTPStorages/company.thebrowser.Browser",
                "~/Library/Logs/Arc",
                "~/Library/Preferences/company.thebrowser.Browser.plist",
                "~/Library/Saved Application State/company.thebrowser.Browser.savedState",
                "~/Library/WebKit/company.thebrowser.Browser",
            ]
        ),
        // MARK: Avast Secure Browser
        Entry(
            name: "Avast Secure Browser",
            bundleIDs: ["com.avast.browser"],
            bundleIDPrefixes: [],
            pathTemplates: [
                "~/Library/Application Support/AvastSoftware/AvastSecureBrowser",
                "~/Library/Caches/com.avast.browser",
                "~/Library/Preferences/com.avast.browser.plist",
            ]
        ),
        // MARK: Azure Data Studio
        Entry(
            name: "Azure Data Studio",
            bundleIDs: ["com.microsoft.azuredatastudio"],
            bundleIDPrefixes: [],
            pathTemplates: [
                "~/Library/Application Support/azuredatastudio",
                "~/Library/Caches/com.microsoft.azuredatastudio",
                "~/Library/Preferences/com.microsoft.azuredatastudio.plist",
                "~/Library/Saved Application State/com.microsoft.azuredatastudio.savedState",
            ]
        ),
        // MARK: Basilisk
        Entry(
            name: "Basilisk",
            bundleIDs: ["org.basilisk.basilisk"],
            bundleIDPrefixes: [],
            pathTemplates: [
                "~/Library/Application Support/Basilisk",
                "~/Library/Caches/org.basilisk.basilisk",
                "~/Library/Preferences/org.basilisk.basilisk.plist",
            ]
        ),
        // MARK: BBEdit
        Entry(
            name: "BBEdit",
            bundleIDs: ["com.barebones.bbedit"],
            bundleIDPrefixes: [],
            pathTemplates: [
                "~/Library/Application Support/BBEdit",
                "~/Library/Caches/com.barebones.bbedit",
                "~/Library/Preferences/com.barebones.bbedit.plist",
            ]
        ),
        // MARK: Beyond Compare
        Entry(
            name: "Beyond Compare",
            bundleIDs: ["com.scootersoftware.beyondcompare"],
            bundleIDPrefixes: [],
            pathTemplates: [
                "~/Library/Application Support/Beyond Compare",
                "~/Library/Preferences/com.ScooterSoftware.BeyondCompare.plist",
            ]
        ),
        // MARK: Bitwarden
        Entry(
            name: "Bitwarden",
            bundleIDs: ["com.bitwarden.desktop"],
            bundleIDPrefixes: [],
            pathTemplates: [
                "~/.config/Bitwarden CLI",
                "~/Library/Application Support/Bitwarden",
                "~/Library/Caches/com.bitwarden.desktop",
                "~/Library/Preferences/com.bitwarden.desktop.plist",
            ]
        ),
        // MARK: Brave Browser
        Entry(
            name: "Brave Browser",
            bundleIDs: ["com.brave.browser"],
            bundleIDPrefixes: [],
            pathTemplates: [
                "~/Library/Application Support/BraveSoftware/Brave-Browser",
                "~/Library/Caches/com.brave.Browser",
                "~/Library/Caches/com.brave.Browser.ShipIt",
                "~/Library/Logs/BraveSoftware",
                "~/Library/Preferences/com.brave.Browser.plist",
                "~/Library/Saved Application State/com.brave.Browser.savedState",
            ]
        ),
        // MARK: Brave Browser Beta / Nightly
        Entry(
            name: "Brave Browser Beta / Nightly",
            bundleIDs: ["com.brave.browser.beta", "com.brave.browser.nightly"],
            bundleIDPrefixes: [],
            pathTemplates: [
                "~/Library/Application Support/BraveSoftware/Brave-Browser-Beta",
                "~/Library/Application Support/BraveSoftware/Brave-Browser-Nightly",
                "~/Library/Caches/com.brave.Browser.beta",
                "~/Library/Caches/com.brave.Browser.nightly",
            ]
        ),
        // MARK: Bruno
        Entry(
            name: "Bruno",
            bundleIDs: ["com.usebruno.app"],
            bundleIDPrefixes: [],
            pathTemplates: [
                "~/Library/Application Support/Bruno",
                "~/Library/Caches/com.usebruno.app",
                "~/Library/Preferences/com.usebruno.app.plist",
            ]
        ),
        // MARK: Camino (discontinued)
        Entry(
            name: "Camino (discontinued)",
            bundleIDs: ["org.mozilla.camino"],
            bundleIDPrefixes: [],
            pathTemplates: [
                "~/Library/Application Support/Camino",
                "~/Library/Preferences/org.mozilla.camino.plist",
            ]
        ),
        // MARK: CCleaner Browser
        Entry(
            name: "CCleaner Browser",
            bundleIDs: ["com.piriform.ccleaner.browser"],
            bundleIDPrefixes: [],
            pathTemplates: [
                "~/Library/Application Support/CCleaner Browser",
                "~/Library/Caches/com.piriform.ccleaner.browser",
                "~/Library/Preferences/com.piriform.ccleaner.browser.plist",
            ]
        ),
        // MARK: Charles Proxy
        Entry(
            name: "Charles Proxy",
            bundleIDs: ["com.xk72.charles"],
            bundleIDPrefixes: [],
            pathTemplates: [
                "~/Library/Application Support/Charles",
                "~/Library/Caches/com.xk72.Charles",
                "~/Library/Logs/Charles",
                "~/Library/Preferences/com.xk72.Charles.plist",
            ]
        ),
        // MARK: Chromium (unbranded)
        Entry(
            name: "Chromium (unbranded)",
            bundleIDs: ["org.chromium.chromium"],
            bundleIDPrefixes: [],
            pathTemplates: [
                "~/Library/Application Support/Chromium",
                "~/Library/Caches/org.chromium.Chromium",
                "~/Library/Preferences/org.chromium.Chromium.plist",
            ]
        ),
        // MARK: Coast by Opera (discontinued)
        Entry(
            name: "Coast by Opera (discontinued)",
            bundleIDs: ["com.opera.coastmac"],
            bundleIDPrefixes: [],
            pathTemplates: [
                "~/Library/Application Support/Coast",
                "~/Library/Preferences/com.opera.CoastMac.plist",
            ]
        ),
        // MARK: Cursor (VS Code Fork)
        Entry(
            name: "Cursor (VS Code Fork)",
            bundleIDs: ["com.todesktop.230313mzl4w4u92"],
            bundleIDPrefixes: [],
            pathTemplates: [
                "~/.cursor",
                "~/Library/Application Support/Cursor",
                "~/Library/Caches/com.todesktop.230313mzl4w4u92",
                "~/Library/HTTPStorages/com.todesktop.230313mzl4w4u92",
                "~/Library/Preferences/com.todesktop.230313mzl4w4u92.plist",
                "~/Library/Saved Application State/com.todesktop.230313mzl4w4u92.savedState",
            ]
        ),
        // MARK: Dash
        Entry(
            name: "Dash",
            bundleIDs: ["com.kapeli.dashdoc"],
            bundleIDPrefixes: [],
            pathTemplates: [
                "~/Library/Application Support/Dash",
                "~/Library/Caches/com.kapeli.dashdoc",
                "~/Library/Preferences/com.kapeli.dashdoc.plist",
                "~/Library/Saved Application State/com.kapeli.dashdoc.savedState",
            ]
        ),
        // MARK: DataGrip (JetBrains)
        Entry(
            name: "DataGrip (JetBrains)",
            bundleIDs: ["com.jetbrains.datagrip"],
            bundleIDPrefixes: [],
            pathTemplates: [
                "~/Library/Application Support/JetBrains/DataGrip*",
                "~/Library/Caches/JetBrains/DataGrip*",
                "~/Library/Logs/JetBrains/DataGrip*",
                "~/Library/Preferences/com.jetbrains.datagrip.plist",
            ]
        ),
        // MARK: DBeaver
        Entry(
            name: "DBeaver",
            bundleIDs: ["org.jkiss.dbeaver.core.product"],
            bundleIDPrefixes: [],
            pathTemplates: [
                "~/Library/Application Support/DBeaverData",
                "~/Library/Caches/org.jkiss.dbeaver.core.product",
                "~/Library/DBeaverData",
                "~/Library/Preferences/org.jkiss.dbeaver.core.product.plist",
                "~/Library/Saved Application State/org.jkiss.dbeaver.core.product.savedState",
            ]
        ),
        // MARK: DevDocs (desktop app)
        Entry(
            name: "DevDocs (desktop app)",
            bundleIDs: ["io.devdocs.desktop"],
            bundleIDPrefixes: [],
            pathTemplates: [
                "~/Library/Application Support/DevDocs",
                "~/Library/Caches/io.devdocs.desktop",
                "~/Library/Preferences/io.devdocs.desktop.plist",
            ]
        ),
        // MARK: DevUtils
        Entry(
            name: "DevUtils",
            bundleIDs: ["com.devutils.app"],
            bundleIDPrefixes: [],
            pathTemplates: [
                "~/Library/Application Support/DevUtils",
                "~/Library/Preferences/com.devutils.app.plist",
            ]
        ),
        // MARK: Docker Desktop
        Entry(
            name: "Docker Desktop",
            bundleIDs: ["com.docker.docker"],
            bundleIDPrefixes: [],
            pathTemplates: [
                "/Library/LaunchDaemons/com.docker.socket.plist",
                "/Library/LaunchDaemons/com.docker.vmnetd.plist",
                "/Library/PrivilegedHelperTools/com.docker.vmnetd",
                "~/Library/Application Support/Docker Desktop",
                "~/Library/Caches/Docker Desktop",
                "~/Library/Caches/com.docker.docker",
                "~/Library/Containers/com.docker.docker",
                "~/Library/Group Containers/group.com.docker",
                "~/Library/HTTPStorages/com.docker.docker",
                "~/Library/Logs/Docker Desktop",
                "~/Library/Preferences/com.docker.docker.plist",
                "~/Library/Preferences/com.docker.helper.plist",
                "~/Library/Saved Application State/com.docker.docker.savedState",
            ]
        ),
        // MARK: DuckDuckGo Browser
        Entry(
            name: "DuckDuckGo Browser",
            bundleIDs: ["com.duckduckgo.macos.browser"],
            bundleIDPrefixes: [],
            pathTemplates: [
                "~/Library/Application Support/DuckDuckGo",
                "~/Library/Caches/com.duckduckgo.macos.browser",
                "~/Library/Preferences/com.duckduckgo.macos.browser.plist",
            ]
        ),
        // MARK: Epic Privacy Browser
        Entry(
            name: "Epic Privacy Browser",
            bundleIDs: ["com.hiddenreflex.epic"],
            bundleIDPrefixes: [],
            pathTemplates: [
                "~/Library/Application Support/Epic",
                "~/Library/Caches/com.hiddenreflex.epic",
                "~/Library/Preferences/com.hiddenreflex.epic.plist",
            ]
        ),
        // MARK: Espresso
        Entry(
            name: "Espresso",
            bundleIDs: ["com.macrabbit.espresso"],
            bundleIDPrefixes: [],
            pathTemplates: [
                "~/Library/Application Support/Espresso",
                "~/Library/Preferences/com.macrabbit.Espresso.plist",
            ]
        ),
        // MARK: Figma (Desktop)
        Entry(
            name: "Figma (Desktop)",
            bundleIDs: ["com.figma.desktop"],
            bundleIDPrefixes: [],
            pathTemplates: [
                "~/Library/Application Support/Figma",
                "~/Library/Caches/com.figma.Desktop",
                "~/Library/Caches/com.figma.Desktop.ShipIt",
                "~/Library/Logs/Figma",
                "~/Library/Preferences/com.figma.Desktop.plist",
                "~/Library/Saved Application State/com.figma.Desktop.savedState",
            ]
        ),
        // MARK: Firefox Developer Edition
        Entry(
            name: "Firefox Developer Edition",
            bundleIDs: ["org.mozilla.firefoxdeveloperedition"],
            bundleIDPrefixes: [],
            pathTemplates: [
                "~/Library/Application Support/Firefox/Profiles/*.dev-edition-default*",
                "~/Library/Caches/org.mozilla.firefoxdeveloperedition",
                "~/Library/Preferences/org.mozilla.firefoxdeveloperedition.plist",
            ]
        ),
        // MARK: Firefox ESR
        Entry(
            name: "Firefox ESR",
            bundleIDs: ["org.mozilla.firefox_esr"],
            bundleIDPrefixes: [],
            pathTemplates: [
                "~/Library/Application Support/Firefox/Profiles/*.default-esr*",
                "~/Library/Caches/org.mozilla.firefox_esr",
                "~/Library/Preferences/org.mozilla.firefox_esr.plist",
            ]
        ),
        // MARK: Firefox Nightly
        Entry(
            name: "Firefox Nightly",
            bundleIDs: ["org.mozilla.nightly"],
            bundleIDPrefixes: [],
            pathTemplates: [
                "~/Library/Application Support/Firefox/Profiles/*.default-nightly*",
                "~/Library/Caches/org.mozilla.nightly",
                "~/Library/Preferences/org.mozilla.nightly.plist",
            ]
        ),
        // MARK: Floorp
        Entry(
            name: "Floorp",
            bundleIDs: ["net.ablaze.floorp"],
            bundleIDPrefixes: [],
            pathTemplates: [
                "~/Library/Application Support/Floorp",
                "~/Library/Caches/net.ablaze.floorp",
                "~/Library/Preferences/net.ablaze.floorp.plist",
            ]
        ),
        // MARK: Fork
        Entry(
            name: "Fork",
            bundleIDs: ["com.danpristupov.fork"],
            bundleIDPrefixes: [],
            pathTemplates: [
                "~/Library/Application Support/com.DanPristupov.Fork",
                "~/Library/Caches/com.DanPristupov.Fork",
                "~/Library/Preferences/com.DanPristupov.Fork.plist",
            ]
        ),
        // MARK: Framer
        Entry(
            name: "Framer",
            bundleIDs: ["com.framer.desktop"],
            bundleIDPrefixes: [],
            pathTemplates: [
                "~/Library/Application Support/Framer",
                "~/Library/Caches/com.framer.desktop",
                "~/Library/Preferences/com.framer.desktop.plist",
                "~/Library/Saved Application State/com.framer.desktop.savedState",
            ]
        ),
        // MARK: Ghostery Browser
        Entry(
            name: "Ghostery Browser",
            bundleIDs: ["com.ghostery.browser"],
            bundleIDPrefixes: [],
            pathTemplates: [
                "~/Library/Application Support/Ghostery",
                "~/Library/Caches/com.ghostery.browser",
                "~/Library/Preferences/com.ghostery.browser.plist",
            ]
        ),
        // MARK: GitHub Desktop
        Entry(
            name: "GitHub Desktop",
            bundleIDs: ["com.github.githubclient"],
            bundleIDPrefixes: [],
            pathTemplates: [
                "~/Library/Application Support/GitHub Desktop",
                "~/Library/Caches/com.github.GitHubClient",
                "~/Library/Caches/com.github.GitHubClient.ShipIt",
                "~/Library/HTTPStorages/com.github.GitHubClient",
                "~/Library/Logs/GitHub Desktop",
                "~/Library/Preferences/com.github.GitHubClient.plist",
                "~/Library/Saved Application State/com.github.GitHubClient.savedState",
            ]
        ),
        // MARK: GitKraken
        Entry(
            name: "GitKraken",
            bundleIDs: ["com.axosoft.gitkraken"],
            bundleIDPrefixes: [],
            pathTemplates: [
                "~/Library/Application Support/GitKraken",
                "~/Library/Caches/com.axosoft.GitKraken",
                "~/Library/Caches/com.axosoft.GitKraken.ShipIt",
                "~/Library/Logs/GitKraken",
                "~/Library/Preferences/com.axosoft.GitKraken.plist",
                "~/Library/Saved Application State/com.axosoft.GitKraken.savedState",
            ]
        ),
        // MARK: Gitpod Desktop
        Entry(
            name: "Gitpod Desktop",
            bundleIDs: ["io.gitpod.gitpod-desktop"],
            bundleIDPrefixes: [],
            pathTemplates: [
                "~/Library/Application Support/Gitpod",
                "~/Library/Caches/io.gitpod.gitpod-desktop",
                "~/Library/Preferences/io.gitpod.gitpod-desktop.plist",
            ]
        ),
        // MARK: Google Chrome
        Entry(
            name: "Google Chrome",
            bundleIDs: ["com.google.chrome"],
            bundleIDPrefixes: [],
            pathTemplates: [
                "/Library/Application Support/Google/Chrome",
                "~/Library/Application Support/Google/Chrome",
                "~/Library/Caches/Google/Chrome",
                "~/Library/Caches/com.google.Chrome",
                "~/Library/Caches/com.google.Chrome.ShipIt",
                "~/Library/HTTPStorages/com.google.Chrome",
                "~/Library/Logs/Google/Chrome",
                "~/Library/Preferences/com.google.Chrome.helper.plist",
                "~/Library/Preferences/com.google.Chrome.plist",
                "~/Library/Saved Application State/com.google.Chrome.savedState",
                "~/Library/WebKit/com.google.Chrome",
            ]
        ),
        // MARK: Google Chrome Canary
        Entry(
            name: "Google Chrome Canary",
            bundleIDs: ["com.google.chrome.canary"],
            bundleIDPrefixes: [],
            pathTemplates: [
                "~/Library/Application Support/Google/Chrome Canary",
                "~/Library/Caches/com.google.Chrome.canary",
                "~/Library/Preferences/com.google.Chrome.canary.plist",
                "~/Library/Saved Application State/com.google.Chrome.canary.savedState",
            ]
        ),
        // MARK: Hoppscotch
        Entry(
            name: "Hoppscotch",
            bundleIDs: ["io.hoppscotch.desktop"],
            bundleIDPrefixes: [],
            pathTemplates: [
                "~/Library/Application Support/Hoppscotch",
                "~/Library/Caches/io.hoppscotch.desktop",
                "~/Library/Preferences/io.hoppscotch.desktop.plist",
            ]
        ),
        // MARK: HTTPie Desktop
        Entry(
            name: "HTTPie Desktop",
            bundleIDs: ["io.httpie.desktop"],
            bundleIDPrefixes: [],
            pathTemplates: [
                "~/Library/Application Support/HTTPie",
                "~/Library/Caches/io.httpie.desktop",
                "~/Library/Preferences/io.httpie.desktop.plist",
            ]
        ),
        // MARK: Hyper
        Entry(
            name: "Hyper",
            bundleIDs: ["co.zeit.hyper"],
            bundleIDPrefixes: [],
            pathTemplates: [
                "~/.hyper.js",
                "~/.hyper_plugins",
                "~/Library/Application Support/Hyper",
                "~/Library/Caches/co.zeit.hyper",
                "~/Library/Preferences/co.zeit.hyper.plist",
            ]
        ),
        // MARK: iCab
        Entry(
            name: "iCab",
            bundleIDs: ["de.icab.icab"],
            bundleIDPrefixes: [],
            pathTemplates: [
                "~/Library/Application Support/iCab",
                "~/Library/Preferences/de.icab.iCab.plist",
            ]
        ),
        // MARK: Insomnia
        Entry(
            name: "Insomnia",
            bundleIDs: ["com.insomnia.app"],
            bundleIDPrefixes: [],
            pathTemplates: [
                "~/Library/Application Support/Insomnia",
                "~/Library/Caches/com.insomnia.app",
                "~/Library/Caches/com.insomnia.app.ShipIt",
                "~/Library/Preferences/com.insomnia.app.plist",
                "~/Library/Saved Application State/com.insomnia.app.savedState",
            ]
        ),
        // MARK: iStat Menus
        Entry(
            name: "iStat Menus",
            bundleIDs: ["com.bjango.istatmenus"],
            bundleIDPrefixes: [],
            pathTemplates: [
                "~/Library/Application Support/iStat Menus",
                "~/Library/Caches/com.bjango.istatmenus",
                "~/Library/Preferences/com.bjango.istatmenus.plist",
                "~/Library/Preferences/com.bjango.istatmenus.status.plist",
            ]
        ),
        // MARK: iTerm2
        Entry(
            name: "iTerm2",
            bundleIDs: ["com.googlecode.iterm2"],
            bundleIDPrefixes: [],
            pathTemplates: [
                "~/Library/Application Support/iTerm2",
                "~/Library/Caches/com.googlecode.iterm2",
                "~/Library/HTTPStorages/com.googlecode.iterm2",
                "~/Library/Preferences/com.googlecode.iterm2.plist",
                "~/Library/Saved Application State/com.googlecode.iterm2.savedState",
            ]
        ),
        // MARK: JetBrains IDEs (IntelliJ IDEA, PyCharm, WebStorm, CLion, GoLand, Rider, DataGrip, RubyMine, PhpStorm, AppCode)
        Entry(
            name: "JetBrains IDEs (IntelliJ IDEA, PyCharm, WebStorm, CLion, GoLand, Rider, DataGrip, RubyMine, PhpStorm, AppCode)",
            bundleIDs: [],
            bundleIDPrefixes: ["com.jetbrains."],
            pathTemplates: [
                "~/Library/Application Support/JetBrains",
                "~/Library/Caches/JetBrains",
                "~/Library/HTTPStorages/com.jetbrains.*",
                "~/Library/Logs/JetBrains",
                "~/Library/Preferences/com.jetbrains.*.plist",
                "~/Library/Saved Application State/com.jetbrains.*.savedState",
                "~/Library/WebKit/com.jetbrains.*",
            ]
        ),
        // MARK: Kaleidoscope
        Entry(
            name: "Kaleidoscope",
            bundleIDs: ["com.blackpixel.kaleidoscope"],
            bundleIDPrefixes: [],
            pathTemplates: [
                "~/Library/Application Support/Kaleidoscope",
                "~/Library/Caches/com.blackpixel.kaleidoscope",
                "~/Library/Preferences/com.blackpixel.kaleidoscope.plist",
            ]
        ),
        // MARK: Karabiner-Elements
        Entry(
            name: "Karabiner-Elements",
            bundleIDs: ["org.pqrs.karabiner-elements.preferences"],
            bundleIDPrefixes: [],
            pathTemplates: [
                "/Library/Application Support/org.pqrs/Karabiner-Elements",
                "/Library/LaunchDaemons/org.pqrs.karabiner.agent.plist",
                "/Library/LaunchDaemons/org.pqrs.karabiner.kextd.plist",
                "~/.config/karabiner",
                "~/.local/share/karabiner",
                "~/Library/Preferences/org.pqrs.Karabiner-Elements.plist",
            ]
        ),
        // MARK: KeePassXC
        Entry(
            name: "KeePassXC",
            bundleIDs: ["org.keepassx.keepassxc"],
            bundleIDPrefixes: [],
            pathTemplates: [
                "~/Library/Application Support/KeePassXC",
                "~/Library/Caches/org.keepassx.keepassxc",
                "~/Library/Preferences/org.keepassx.keepassxc.plist",
            ]
        ),
        // MARK: Kitty
        Entry(
            name: "Kitty",
            bundleIDs: ["net.kovidgoyal.kitty"],
            bundleIDPrefixes: [],
            pathTemplates: [
                "~/.cache/kitty",
                "~/.config/kitty",
                "~/Library/Preferences/net.kovidgoyal.kitty.plist",
            ]
        ),
        // MARK: LibreWolf
        Entry(
            name: "LibreWolf",
            bundleIDs: ["io.gitlab.librewolf-community"],
            bundleIDPrefixes: [],
            pathTemplates: [
                "~/Library/Application Support/LibreWolf",
                "~/Library/Caches/io.gitlab.librewolf-community",
                "~/Library/Preferences/io.gitlab.librewolf-community.plist",
            ]
        ),
        // MARK: Lunascape
        Entry(
            name: "Lunascape",
            bundleIDs: ["jp.lunascape.lunascape"],
            bundleIDPrefixes: [],
            pathTemplates: [
                "~/Library/Application Support/Lunascape",
                "~/Library/Caches/jp.lunascape.lunascape",
                "~/Library/Preferences/jp.lunascape.lunascape.plist",
            ]
        ),
        // MARK: Maccy (clipboard manager)
        Entry(
            name: "Maccy (clipboard manager)",
            bundleIDs: ["org.p0deje.maccy"],
            bundleIDPrefixes: [],
            pathTemplates: [
                "~/Library/Containers/org.p0deje.Maccy",
                "~/Library/Preferences/org.p0deje.Maccy.plist",
            ]
        ),
        // MARK: Maxthon Browser
        Entry(
            name: "Maxthon Browser",
            bundleIDs: ["com.maxthon.mac.maxthon"],
            bundleIDPrefixes: [],
            pathTemplates: [
                "~/Library/Application Support/Maxthon",
                "~/Library/Caches/com.maxthon.mac.maxthon",
                "~/Library/Preferences/com.maxthon.mac.maxthon.plist",
            ]
        ),
        // MARK: Microsoft Edge
        Entry(
            name: "Microsoft Edge",
            bundleIDs: ["com.microsoft.edgemac"],
            bundleIDPrefixes: [],
            pathTemplates: [
                "~/Library/Application Support/Microsoft Edge",
                "~/Library/Caches/com.microsoft.edgemac",
                "~/Library/Caches/com.microsoft.edgemac.ShipIt",
                "~/Library/HTTPStorages/com.microsoft.edgemac",
                "~/Library/Logs/Microsoft Edge",
                "~/Library/Preferences/com.microsoft.edgemac.plist",
                "~/Library/Saved Application State/com.microsoft.edgemac.savedState",
            ]
        ),
        // MARK: Microsoft Edge Dev / Beta / Canary
        Entry(
            name: "Microsoft Edge Dev / Beta / Canary",
            bundleIDs: ["com.microsoft.edgemac.dev", "com.microsoft.edgemac.beta", "com.microsoft.edgemac.canary"],
            bundleIDPrefixes: [],
            pathTemplates: [
                "~/Library/Application Support/Microsoft Edge Beta",
                "~/Library/Application Support/Microsoft Edge Canary",
                "~/Library/Application Support/Microsoft Edge Dev",
                "~/Library/Caches/com.microsoft.edgemac.Beta",
                "~/Library/Caches/com.microsoft.edgemac.Canary",
                "~/Library/Caches/com.microsoft.edgemac.Dev",
            ]
        ),
        // MARK: MongoDB Compass
        Entry(
            name: "MongoDB Compass",
            bundleIDs: ["com.mongodb.compass"],
            bundleIDPrefixes: [],
            pathTemplates: [
                "~/Library/Application Support/MongoDB Compass",
                "~/Library/Caches/com.mongodb.compass",
                "~/Library/Preferences/com.mongodb.compass.plist",
                "~/Library/Saved Application State/com.mongodb.compass.savedState",
            ]
        ),
        // MARK: Mozilla Firefox
        Entry(
            name: "Mozilla Firefox",
            bundleIDs: ["org.mozilla.firefox"],
            bundleIDPrefixes: [],
            pathTemplates: [
                "~/Library/Application Support/Firefox",
                "~/Library/Caches/Firefox",
                "~/Library/Caches/org.mozilla.firefox",
                "~/Library/Logs/Firefox",
                "~/Library/Preferences/org.mozilla.firefox.plist",
                "~/Library/Saved Application State/org.mozilla.firefox.savedState",
            ]
        ),
        // MARK: Mullvad Browser
        Entry(
            name: "Mullvad Browser",
            bundleIDs: ["net.mullvad.mullvadbrowser"],
            bundleIDPrefixes: [],
            pathTemplates: [
                "~/Library/Application Support/MullvadBrowser",
                "~/Library/Caches/net.mullvad.MullvadBrowser",
                "~/Library/Preferences/net.mullvad.MullvadBrowser.plist",
            ]
        ),
        // MARK: MySQL Workbench
        Entry(
            name: "MySQL Workbench",
            bundleIDs: ["com.oracle.mysql.workbench"],
            bundleIDPrefixes: [],
            pathTemplates: [
                "~/Library/Application Support/MySQL/Workbench",
                "~/Library/Caches/com.oracle.mysql.workbench",
                "~/Library/Preferences/com.oracle.mysql.workbench.plist",
            ]
        ),
        // MARK: Navicat
        Entry(
            name: "Navicat",
            bundleIDs: ["com.navicat.navicatpremium"],
            bundleIDPrefixes: [],
            pathTemplates: [
                "~/Library/Application Support/PremiumSoft CyberTech/Navicat",
                "~/Library/Caches/com.navicat.NavicatPremium",
                "~/Library/Preferences/com.navicat.NavicatPremium.plist",
            ]
        ),
        // MARK: Nova (Panic)
        Entry(
            name: "Nova (Panic)",
            bundleIDs: ["com.panic.nova"],
            bundleIDPrefixes: [],
            pathTemplates: [
                "~/Library/Application Support/Nova",
                "~/Library/Caches/com.panic.Nova",
                "~/Library/Preferences/com.panic.Nova.plist",
                "~/Library/Saved Application State/com.panic.Nova.savedState",
            ]
        ),
        // MARK: OmniWeb
        Entry(
            name: "OmniWeb",
            bundleIDs: ["com.omnigroup.omniweb5"],
            bundleIDPrefixes: [],
            pathTemplates: [
                "~/Library/Application Support/OmniWeb",
                "~/Library/Caches/com.omnigroup.OmniWeb5",
                "~/Library/Preferences/com.omnigroup.OmniWeb5.plist",
            ]
        ),
        // MARK: Opera
        Entry(
            name: "Opera",
            bundleIDs: ["com.operasoftware.opera"],
            bundleIDPrefixes: [],
            pathTemplates: [
                "~/Library/Application Support/com.operasoftware.Opera",
                "~/Library/Caches/com.operasoftware.Opera",
                "~/Library/Preferences/com.operasoftware.Opera.plist",
                "~/Library/Saved Application State/com.operasoftware.Opera.savedState",
            ]
        ),
        // MARK: Opera Developer
        Entry(
            name: "Opera Developer",
            bundleIDs: ["com.operasoftware.operadeveloperedition"],
            bundleIDPrefixes: [],
            pathTemplates: [
                "~/Library/Application Support/com.operasoftware.OperaDeveloperEdition",
                "~/Library/Caches/com.operasoftware.OperaDeveloperEdition",
            ]
        ),
        // MARK: Opera GX
        Entry(
            name: "Opera GX",
            bundleIDs: ["com.operasoftware.operagx"],
            bundleIDPrefixes: [],
            pathTemplates: [
                "~/Library/Application Support/com.operasoftware.OperaGX",
                "~/Library/Caches/com.operasoftware.OperaGX",
                "~/Library/Preferences/com.operasoftware.OperaGX.plist",
            ]
        ),
        // MARK: OrbStack
        Entry(
            name: "OrbStack",
            bundleIDs: ["dev.orbstack.orbstack"],
            bundleIDPrefixes: [],
            pathTemplates: [
                "~/.orbstack",
                "~/Library/Application Support/OrbStack",
                "~/Library/Caches/dev.orbstack.OrbStack",
                "~/Library/Logs/OrbStack",
                "~/Library/Preferences/dev.orbstack.OrbStack.plist",
                "~/Library/Saved Application State/dev.orbstack.OrbStack.savedState",
            ]
        ),
        // MARK: Orion
        Entry(
            name: "Orion",
            bundleIDs: ["com.kagi.kagimacos"],
            bundleIDPrefixes: [],
            pathTemplates: [
                "~/Library/Application Support/Orion",
                "~/Library/Caches/com.kagi.kagimacOS",
                "~/Library/Preferences/com.kagi.kagimacOS.plist",
            ]
        ),
        // MARK: Pale Moon
        Entry(
            name: "Pale Moon",
            bundleIDs: ["org.palemoon.palemoon"],
            bundleIDPrefixes: [],
            pathTemplates: [
                "~/Library/Application Support/Pale Moon",
                "~/Library/Caches/org.palemoon.PaleMoon",
                "~/Library/Preferences/org.palemoon.PaleMoon.plist",
            ]
        ),
        // MARK: Paste (clipboard manager)
        Entry(
            name: "Paste (clipboard manager)",
            bundleIDs: ["com.wiheads.paste"],
            bundleIDPrefixes: [],
            pathTemplates: [
                "~/Library/Application Support/Paste",
                "~/Library/Caches/com.wiheads.paste",
                "~/Library/Containers/com.wiheads.paste",
                "~/Library/Preferences/com.wiheads.paste.plist",
            ]
        ),
        // MARK: pgAdmin 4
        Entry(
            name: "pgAdmin 4",
            bundleIDs: ["org.pgadmin.pgadmin4"],
            bundleIDPrefixes: [],
            pathTemplates: [
                "~/Library/Application Support/pgAdmin",
                "~/Library/Caches/org.pgadmin.pgadmin4",
                "~/Library/Preferences/org.pgadmin.pgadmin4.plist",
                "~/Library/Saved Application State/org.pgadmin.pgadmin4.savedState",
            ]
        ),
        // MARK: Postman
        Entry(
            name: "Postman",
            bundleIDs: ["com.postmanlabs.mac"],
            bundleIDPrefixes: [],
            pathTemplates: [
                "~/Library/Application Support/Postman",
                "~/Library/Caches/com.postmanlabs.mac",
                "~/Library/Caches/com.postmanlabs.mac.ShipIt",
                "~/Library/HTTPStorages/com.postmanlabs.mac",
                "~/Library/Logs/Postman",
                "~/Library/Preferences/com.postmanlabs.mac.plist",
                "~/Library/Saved Application State/com.postmanlabs.mac.savedState",
            ]
        ),
        // MARK: Principle
        Entry(
            name: "Principle",
            bundleIDs: ["com.danielhooper.principle"],
            bundleIDPrefixes: [],
            pathTemplates: [
                "~/Library/Application Support/Principle",
                "~/Library/Preferences/com.danielhooper.principle.plist",
            ]
        ),
        // MARK: ProtoPie
        Entry(
            name: "ProtoPie",
            bundleIDs: ["studio.protopie"],
            bundleIDPrefixes: [],
            pathTemplates: [
                "~/Library/Application Support/ProtoPie",
                "~/Library/Preferences/studio.protopie.plist",
            ]
        ),
        // MARK: Proxyman
        Entry(
            name: "Proxyman",
            bundleIDs: ["com.proxyman.nsproxy"],
            bundleIDPrefixes: [],
            pathTemplates: [
                "~/Library/Application Support/com.proxyman.NSProxy",
                "~/Library/Caches/com.proxyman.NSProxy",
                "~/Library/Preferences/com.proxyman.NSProxy.plist",
            ]
        ),
        // MARK: Rancher Desktop
        Entry(
            name: "Rancher Desktop",
            bundleIDs: ["io.rancher.desktop"],
            bundleIDPrefixes: [],
            pathTemplates: [
                "/Library/LaunchDaemons/io.rancher.desktop.helper.plist",
                "/Library/PrivilegedHelperTools/io.rancher.desktop.helper",
                "~/.local/share/rancher-desktop",
                "~/.rd",
                "~/Library/Application Support/rancher-desktop",
                "~/Library/Caches/io.rancher.desktop",
                "~/Library/Logs/rancher-desktop",
                "~/Library/Preferences/io.rancher.desktop.plist",
                "~/Library/Saved Application State/io.rancher.desktop.savedState",
            ]
        ),
        // MARK: RapidAPI (Paw)
        Entry(
            name: "RapidAPI (Paw)",
            bundleIDs: ["com.luckymarmot.paw"],
            bundleIDPrefixes: [],
            pathTemplates: [
                "~/Library/Application Support/Paw",
                "~/Library/Caches/com.luckymarmot.Paw",
                "~/Library/Preferences/com.luckymarmot.Paw.plist",
            ]
        ),
        // MARK: Raycast (developer-focused launcher)
        Entry(
            name: "Raycast (developer-focused launcher)",
            bundleIDs: ["com.raycast.macos"],
            bundleIDPrefixes: [],
            pathTemplates: [
                "~/Library/Application Support/com.raycast.macos",
                "~/Library/Caches/com.raycast.macos",
                "~/Library/HTTPStorages/com.raycast.macos",
                "~/Library/Preferences/com.raycast.macos.plist",
                "~/Library/Saved Application State/com.raycast.macos.savedState",
            ]
        ),
        // MARK: RedisInsight
        Entry(
            name: "RedisInsight",
            bundleIDs: ["com.redis.redisinsight"],
            bundleIDPrefixes: [],
            pathTemplates: [
                "~/Library/Application Support/RedisInsight",
                "~/Library/Caches/com.redis.RedisInsight",
                "~/Library/Preferences/com.redis.RedisInsight.plist",
            ]
        ),
        // MARK: Roccat Browser
        Entry(
            name: "Roccat Browser",
            bundleIDs: ["com.runecats.roccat"],
            bundleIDPrefixes: [],
            pathTemplates: [
                "~/Library/Application Support/Roccat",
                "~/Library/Preferences/com.runecats.Roccat.plist",
            ]
        ),
        // MARK: SeaMonkey
        Entry(
            name: "SeaMonkey",
            bundleIDs: ["org.mozilla.seamonkey"],
            bundleIDPrefixes: [],
            pathTemplates: [
                "~/Library/Application Support/SeaMonkey",
                "~/Library/Caches/org.mozilla.seamonkey",
                "~/Library/Preferences/org.mozilla.seamonkey.plist",
            ]
        ),
        // MARK: Sequel Ace
        Entry(
            name: "Sequel Ace",
            bundleIDs: ["com.sequel-ace.sequel-ace"],
            bundleIDPrefixes: [],
            pathTemplates: [
                "~/Library/Caches/com.sequel-ace.sequel-ace",
                "~/Library/Containers/com.sequel-ace.sequel-ace",
                "~/Library/Group Containers/com.sequel-ace.sequel-ace",
                "~/Library/Preferences/com.sequel-ace.sequel-ace.plist",
            ]
        ),
        // MARK: Sequel Pro (discontinued)
        Entry(
            name: "Sequel Pro (discontinued)",
            bundleIDs: ["com.sequelpro.sequelpro"],
            bundleIDPrefixes: [],
            pathTemplates: [
                "~/Library/Application Support/Sequel Pro",
                "~/Library/Caches/com.sequelpro.SequelPro",
                "~/Library/Preferences/com.sequelpro.SequelPro.plist",
            ]
        ),
        // MARK: SigmaOS
        Entry(
            name: "SigmaOS",
            bundleIDs: ["com.sigmaos.sigmaos.macos"],
            bundleIDPrefixes: [],
            pathTemplates: [
                "~/Library/Application Support/SigmaOS",
                "~/Library/Caches/com.sigmaos.sigmaos.macos",
                "~/Library/Preferences/com.sigmaos.sigmaos.macos.plist",
            ]
        ),
        // MARK: Simulator (iOS)
        Entry(
            name: "Simulator (iOS)",
            bundleIDs: ["com.apple.iphonesimulator"],
            bundleIDPrefixes: [],
            pathTemplates: [
                "~/Library/Caches/com.apple.dt.Xcode/DVTPortal",
                "~/Library/Caches/com.apple.dt.Xcode/Downloads",
                "~/Library/Developer/CoreSimulator",
            ]
        ),
        // MARK: Sketch
        Entry(
            name: "Sketch",
            bundleIDs: ["com.bohemiancoding.sketch3"],
            bundleIDPrefixes: [],
            pathTemplates: [
                "~/Library/Application Support/com.bohemiancoding.sketch3",
                "~/Library/Caches/com.bohemiancoding.sketch3",
                "~/Library/Preferences/com.bohemiancoding.sketch3.plist",
                "~/Library/Saved Application State/com.bohemiancoding.sketch3.savedState",
            ]
        ),
        // MARK: Sleipnir
        Entry(
            name: "Sleipnir",
            bundleIDs: ["com.fenrir-inc.sleipnir"],
            bundleIDPrefixes: [],
            pathTemplates: [
                "~/Library/Application Support/Sleipnir",
                "~/Library/Caches/com.fenrir-inc.Sleipnir",
                "~/Library/Preferences/com.fenrir-inc.Sleipnir.plist",
            ]
        ),
        // MARK: Sourcetree
        Entry(
            name: "Sourcetree",
            bundleIDs: ["com.torusknot.sourcetreenotmas"],
            bundleIDPrefixes: [],
            pathTemplates: [
                "~/Library/Application Support/SourceTree",
                "~/Library/Caches/com.torusknot.SourceTreeNotMAS",
                "~/Library/Preferences/com.torusknot.SourceTreeNotMAS.plist",
                "~/Library/Saved Application State/com.torusknot.SourceTreeNotMAS.savedState",
            ]
        ),
        // MARK: Stainless
        Entry(
            name: "Stainless",
            bundleIDs: ["com.mesadynamics.stainless"],
            bundleIDPrefixes: [],
            pathTemplates: [
                "~/Library/Application Support/Stainless",
                "~/Library/Preferences/com.mesadynamics.Stainless.plist",
            ]
        ),
        // MARK: Sublime Text
        Entry(
            name: "Sublime Text",
            bundleIDs: ["com.sublimetext.4"],
            bundleIDPrefixes: [],
            pathTemplates: [
                "~/Library/Application Support/Sublime Text",
                "~/Library/Application Support/Sublime Text 3",
                "~/Library/Application Support/Sublime Text 4",
                "~/Library/Application Support/Sublime Text*/Cache",
                "~/Library/Application Support/Sublime Text*/Index",
                "~/Library/Application Support/Sublime Text*/Installed Packages",
                "~/Library/Application Support/Sublime Text*/Local/License.sublime_license",
                "~/Library/Application Support/Sublime Text*/Local/Session.sublime_session",
                "~/Library/Application Support/Sublime Text*/Packages/User",
                "~/Library/Caches/com.sublimetext.4",
                "~/Library/Preferences/com.sublimetext.4.plist",
                "~/Library/Saved Application State/com.sublimetext.4.savedState",
            ]
        ),
        // MARK: Tabby
        Entry(
            name: "Tabby",
            bundleIDs: ["org.tabby"],
            bundleIDPrefixes: [],
            pathTemplates: [
                "~/Library/Application Support/tabby",
                "~/Library/Caches/org.tabby",
                "~/Library/Preferences/org.tabby.plist",
            ]
        ),
        // MARK: TablePlus
        Entry(
            name: "TablePlus",
            bundleIDs: ["com.tableplus.tableplus"],
            bundleIDPrefixes: [],
            pathTemplates: [
                "~/Library/Application Support/com.tableplus.TablePlus",
                "~/Library/Caches/com.tableplus.TablePlus",
                "~/Library/Containers/com.tableplus.TablePlus",
                "~/Library/Logs/TablePlus",
                "~/Library/Preferences/com.tableplus.TablePlus.plist",
                "~/Library/Saved Application State/com.tableplus.TablePlus.savedState",
            ]
        ),
        // MARK: TextMate
        Entry(
            name: "TextMate",
            bundleIDs: ["com.macromates.textmate"],
            bundleIDPrefixes: [],
            pathTemplates: [
                "~/Library/Application Support/TextMate",
                "~/Library/Caches/com.macromates.TextMate",
                "~/Library/Preferences/com.macromates.TextMate.plist",
            ]
        ),
        // MARK: Tor Browser
        Entry(
            name: "Tor Browser",
            bundleIDs: ["org.torproject.torbrowser"],
            bundleIDPrefixes: [],
            pathTemplates: [
                "~/Library/Application Support/TorBrowser-Data",
                "~/Library/Caches/org.torproject.torbrowser",
                "~/Library/Preferences/org.torproject.torbrowser.plist",
            ]
        ),
        // MARK: Tower
        Entry(
            name: "Tower",
            bundleIDs: ["com.fournova.tower3"],
            bundleIDPrefixes: [],
            pathTemplates: [
                "~/Library/Application Support/com.fournova.Tower3",
                "~/Library/Caches/com.fournova.Tower3",
                "~/Library/Preferences/com.fournova.Tower3.plist",
            ]
        ),
        // MARK: UTM
        Entry(
            name: "UTM",
            bundleIDs: ["com.utmapp.utm"],
            bundleIDPrefixes: [],
            pathTemplates: [
                "~/Library/Application Support/UTM",
                "~/Library/Caches/com.utmapp.UTM",
                "~/Library/Containers/com.utmapp.UTM",
                "~/Library/Preferences/com.utmapp.UTM.plist",
                "~/Library/Saved Application State/com.utmapp.UTM.savedState",
            ]
        ),
        // MARK: Vagrant
        Entry(
            name: "Vagrant",
            bundleIDs: ["com.vagrant.vagrant"],
            bundleIDPrefixes: [],
            pathTemplates: [
                "~/.vagrant.d",
                "~/Library/Caches/com.vagrant.vagrant",
            ]
        ),
        // MARK: Visual Studio Code
        Entry(
            name: "Visual Studio Code",
            bundleIDs: ["com.microsoft.vscode"],
            bundleIDPrefixes: [],
            pathTemplates: [
                "~/.vscode",
                "~/Library/Application Support/Code",
                "~/Library/Caches/com.microsoft.VSCode",
                "~/Library/Caches/com.microsoft.VSCode.ShipIt",
                "~/Library/HTTPStorages/com.microsoft.VSCode",
                "~/Library/Logs/Code",
                "~/Library/Preferences/com.microsoft.VSCode.helper.plist",
                "~/Library/Preferences/com.microsoft.VSCode.plist",
                "~/Library/Saved Application State/com.microsoft.VSCode.savedState",
            ]
        ),
        // MARK: Vivaldi
        Entry(
            name: "Vivaldi",
            bundleIDs: ["com.vivaldi.vivaldi"],
            bundleIDPrefixes: [],
            pathTemplates: [
                "~/Library/Application Support/Vivaldi",
                "~/Library/Caches/com.vivaldi.Vivaldi",
                "~/Library/Caches/com.vivaldi.Vivaldi.ShipIt",
                "~/Library/Preferences/com.vivaldi.Vivaldi.plist",
                "~/Library/Saved Application State/com.vivaldi.Vivaldi.savedState",
            ]
        ),
        // MARK: Warp
        Entry(
            name: "Warp",
            bundleIDs: ["dev.warp.warp-stable"],
            bundleIDPrefixes: [],
            pathTemplates: [
                "~/.warp",
                "~/Library/Application Support/dev.warp.Warp-Stable",
                "~/Library/Caches/dev.warp.Warp-Stable",
                "~/Library/HTTPStorages/dev.warp.Warp-Stable",
                "~/Library/Preferences/dev.warp.Warp-Stable.plist",
                "~/Library/Saved Application State/dev.warp.Warp-Stable.savedState",
            ]
        ),
        // MARK: Waterfox
        Entry(
            name: "Waterfox",
            bundleIDs: ["net.waterfox.waterfox"],
            bundleIDPrefixes: [],
            pathTemplates: [
                "~/Library/Application Support/Waterfox",
                "~/Library/Caches/net.waterfox.waterfox",
                "~/Library/Preferences/net.waterfox.waterfox.plist",
            ]
        ),
        // MARK: WezTerm
        Entry(
            name: "WezTerm",
            bundleIDs: ["com.github.wez.wezterm"],
            bundleIDPrefixes: [],
            pathTemplates: [
                "~/.config/wezterm",
                "~/.wezterm.lua",
                "~/Library/Preferences/com.github.wez.wezterm.plist",
            ]
        ),
        // MARK: Windsurf (VS Code Fork by Codeium)
        Entry(
            name: "Windsurf (VS Code Fork by Codeium)",
            bundleIDs: ["com.exafunction.windsurf"],
            bundleIDPrefixes: [],
            pathTemplates: [
                "~/.windsurf",
                "~/Library/Application Support/Windsurf",
                "~/Library/Caches/com.exafunction.windsurf",
                "~/Library/Preferences/com.exafunction.windsurf.plist",
                "~/Library/Saved Application State/com.exafunction.windsurf.savedState",
            ]
        ),
        // MARK: Wireshark
        Entry(
            name: "Wireshark",
            bundleIDs: ["org.wireshark.wireshark"],
            bundleIDPrefixes: [],
            pathTemplates: [
                "~/Library/Application Support/Wireshark",
                "~/Library/Caches/org.wireshark.Wireshark",
                "~/Library/Preferences/org.wireshark.Wireshark.plist",
            ]
        ),
        // MARK: Xcode
        Entry(
            name: "Xcode",
            bundleIDs: ["com.apple.dt.xcode"],
            bundleIDPrefixes: [],
            pathTemplates: [
                "/Library/Application Support/Xcode",
                "~/Library/Caches/com.apple.dt.SourceKitService",
                "~/Library/Caches/com.apple.dt.Xcode",
                "~/Library/Caches/com.apple.dt.XcodePreviews",
                "~/Library/Caches/org.swift.swiftpm",
                "~/Library/Developer/CoreSimulator",
                "~/Library/Developer/Xcode",
                "~/Library/HTTPStorages/com.apple.dt.Xcode",
                "~/Library/Logs/CoreSimulator",
                "~/Library/Logs/DiagnosticReports/SourceKitService*",
                "~/Library/Logs/DiagnosticReports/simulator*",
                "~/Library/Preferences/com.apple.dt.Xcode.plist",
                "~/Library/Preferences/com.apple.dt.xcodebuild.plist",
                "~/Library/Saved Application State/com.apple.dt.Xcode.savedState",
                "~/Library/WebKit/com.apple.dt.Xcode",
            ]
        ),
        // MARK: Yandex Browser
        Entry(
            name: "Yandex Browser",
            bundleIDs: ["ru.yandex.desktop.yandex-browser"],
            bundleIDPrefixes: [],
            pathTemplates: [
                "~/Library/Application Support/Yandex/YandexBrowser",
                "~/Library/Caches/ru.yandex.desktop.yandex-browser",
                "~/Library/Preferences/ru.yandex.desktop.yandex-browser.plist",
            ]
        ),
        // MARK: Zed Editor
        Entry(
            name: "Zed Editor",
            bundleIDs: ["dev.zed.zed"],
            bundleIDPrefixes: [],
            pathTemplates: [
                "~/.config/zed",
                "~/.zed",
                "~/Library/Application Support/Zed",
                "~/Library/Caches/dev.zed.Zed",
                "~/Library/Logs/Zed",
                "~/Library/Preferences/dev.zed.Zed.plist",
            ]
        ),
    ]
}

import Foundation

public actor ApplicationRuleRegistry {
    public static let shared = createDefault()
    private var rules: [ApplicationRule] = []

    public init() {}

    public init(rules: [ApplicationRule]) {
        self.rules = rules
    }

    public static func createDefault() -> ApplicationRuleRegistry {
        ApplicationRuleRegistry(rules: [
            // Narrow / Specific Rules
            ParallelsRule(),
            VMwareFusionRule(),
            DaVinciResolveRule(),
            LogicProRule(),
            FinalCutProRule(),
            RancherDesktopRule(),
            KarabinerElementsRule(),
            LittleSnitchRule(),
            NordVPNRule(),
            AlfredRule(),
            RaycastRule(),
            BrowserRule(),
            JetBrainsRule(),
            DockerRule(),
            XcodeRule(),
            AndroidStudioRule(),
            AdobeRule(),
            MicrosoftOfficeRule(),
            SteamRule(),
            EpicGamesRule(),
            UnityRule(),
            HomebrewRule(),
            // Broad Category Rules
            CloudStorageRule(),
            VirtualizationRule(),
            DatabaseToolsRule(),
            TerminalRule(),
            CommunicationRule(),
            GitClientsRule(),
            NetworkExtensionRule(),
            ElectronRule(),
        ])
    }

    public func bestRule(for identity: AppIdentity) -> ApplicationRule {
        for rule in rules {
            if rule.matches(identity: identity) {
                return rule
            }
        }
        return DefaultRule()
    }
}
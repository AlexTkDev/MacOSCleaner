import Foundation

public actor ApplicationRuleRegistry {
    public static let shared = ApplicationRuleRegistry()
    private var rules: [ApplicationRule] = []

    public init() {}

    public init(rules: [ApplicationRule]) {
        self.rules = rules
    }

    public static func createDefault() -> ApplicationRuleRegistry {
        ApplicationRuleRegistry(rules: [
            // Category Rules
            CloudStorageRule(),
            VirtualizationRule(),
            DatabaseToolsRule(),
            TerminalRule(),
            CommunicationRule(),
            GitClientsRule(),
            // Individual High-Impact Rules
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
            // Existing Rules
            ElectronRule(), BrowserRule(), JetBrainsRule(),
            DockerRule(), XcodeRule(), AndroidStudioRule(),
            AdobeRule(), MicrosoftOfficeRule(), SteamRule(),
            EpicGamesRule(), UnityRule(), HomebrewRule(),
            NetworkExtensionRule(),
        ])
    }

    public func register(_ rule: ApplicationRule) {
        rules.append(rule)
    }

    public func registerAll(_ newRules: [ApplicationRule]) {
        rules.append(contentsOf: newRules)
    }

    public func bestRule(for identity: AppIdentity) -> ApplicationRule {
        for rule in rules {
            if rule.matches(identity: identity) {
                return rule
            }
        }
        return DefaultRule()
    }

    public func allMatchingRules(for identity: AppIdentity) -> [ApplicationRule] {
        rules.filter { $0.matches(identity: identity) }
    }

    public func hasRule(for identity: AppIdentity) -> Bool {
        rules.contains { $0.matches(identity: identity) }
    }
}
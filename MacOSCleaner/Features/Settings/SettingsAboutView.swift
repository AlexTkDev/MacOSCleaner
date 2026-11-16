import SwiftUI

struct AppTransparencyFact: Identifiable {
    let id: String
    let icon: String
    let color: Color
    let titleKey: String
    let descKey: String

    static let guarantees: [AppTransparencyFact] = [
        AppTransparencyFact(id: "g1", icon: "lock.shield.fill", color: .green, titleKey: "settings_privacy_item_1_title", descKey: "settings_privacy_item_1_desc"),
        AppTransparencyFact(id: "g2", icon: "network", color: .blue, titleKey: "settings_privacy_item_2_title", descKey: "settings_privacy_item_2_desc"),
        AppTransparencyFact(id: "g3", icon: "trash.fill", color: .teal, titleKey: "settings_privacy_item_3_title", descKey: "settings_privacy_item_3_desc"),
        AppTransparencyFact(id: "g4", icon: "checkmark.seal.fill", color: .purple, titleKey: "settings_privacy_item_4_title", descKey: "settings_privacy_item_4_desc"),
        AppTransparencyFact(id: "g5", icon: "exclamationmark.shield.fill", color: .orange, titleKey: "settings_privacy_item_5_title", descKey: "settings_privacy_item_5_desc"),
        AppTransparencyFact(id: "g6", icon: "cpu.fill", color: .pink, titleKey: "settings_privacy_item_6_title", descKey: "settings_privacy_item_6_desc"),
        AppTransparencyFact(id: "g7", icon: "hand.raised.fill", color: .yellow, titleKey: "settings_privacy_item_7_title", descKey: "settings_privacy_item_7_desc"),
        AppTransparencyFact(id: "g8", icon: "xmark.app.fill", color: .indigo, titleKey: "settings_privacy_item_8_title", descKey: "settings_privacy_item_8_desc"),
        AppTransparencyFact(id: "g9", icon: "key.fill", color: .cyan, titleKey: "settings_privacy_item_9_title", descKey: "settings_privacy_item_9_desc"),
    ]

    static let limitations: [AppTransparencyFact] = [
        AppTransparencyFact(id: "l1", icon: "shield.slash", color: .secondary, titleKey: "about_limit_no_antivirus_title", descKey: "about_limit_no_antivirus_desc"),
        AppTransparencyFact(id: "l2", icon: "lock.doc", color: .orange, titleKey: "about_limit_tcc_title", descKey: "about_limit_tcc_desc"),
        AppTransparencyFact(id: "l3", icon: "network.badge.shield.half.filled", color: .blue, titleKey: "about_limit_network_title", descKey: "about_limit_network_desc"),
        AppTransparencyFact(id: "l4", icon: "puzzlepiece.extension", color: .purple, titleKey: "about_limit_extensions_title", descKey: "about_limit_extensions_desc"),
        AppTransparencyFact(id: "l5", icon: "bolt.slash", color: .secondary, titleKey: "about_limit_no_daemon_title", descKey: "about_limit_no_daemon_desc"),
    ]
}

struct SettingsAboutView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                linksCard
                privacySafetyCard
                knownLimitationsCard
            }
            .padding(20)
        }
    }

    private var linksCard: some View {
        GlassCard(
            header: {
                SettingsSectionHeader("settings_about_resources".localized, subtitle: "settings_about_resources_sub".localized, iconName: "link", iconColor: .cyan)
            },
            content: {
                VStack(spacing: 8) {
                    linkRow("settings_about_star_github".localized, subtitle: "https://github.com/AlexTkDev/MacOSCleaner", icon: "star.fill", iconColor: .yellow, url: "https://github.com/AlexTkDev/MacOSCleaner")
                    SettingsDivider()
                    linkRow("settings_about_github".localized, subtitle: "https://github.com/AlexTkDev/MacOSCleaner", icon: "curlybraces.square.fill", iconColor: .blue, url: "https://github.com/AlexTkDev/MacOSCleaner")
                    SettingsDivider()
                    linkRow("settings_about_github_releases".localized, subtitle: "https://github.com/AlexTkDev/MacOSCleaner/releases", icon: "arrow.down.app.fill", iconColor: .green, url: "https://github.com/AlexTkDev/MacOSCleaner/releases")
                    SettingsDivider()
                    linkRow("settings_about_wiki".localized, subtitle: "settings_about_wiki_sub".localized, icon: "text.book.closed.fill", iconColor: .purple, url: "https://github.com/AlexTkDev/MacOSCleaner/wiki")
                    SettingsDivider()
                    linkRow("settings_about_report_issue".localized, subtitle: "https://github.com/AlexTkDev/MacOSCleaner/issues", icon: "ladybug.fill", iconColor: .orange, url: "https://github.com/AlexTkDev/MacOSCleaner/issues")
                    SettingsDivider()
                    linkRow("settings_about_website".localized, subtitle: "https://alextkdev.github.io/MacOSCleaner/", icon: "globe", iconColor: .cyan, url: "https://alextkdev.github.io/MacOSCleaner/")
                    SettingsDivider()
                    linkRow("settings_about_orcid".localized, subtitle: "https://orcid.org/0009-0002-8907-5406", icon: "person.text.rectangle", iconColor: .green, url: "https://orcid.org/0009-0002-8907-5406")
                }
            }
        )
    }

    private func linkRow(_ title: String, subtitle: String, icon: String, iconColor: Color, url: String) -> some View {
        Button {
            if let linkURL = URL(string: url) {
                NSWorkspace.shared.open(linkURL)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.body)
                    .foregroundStyle(iconColor)
                    .frame(width: 32, height: 32)
                    .background(iconColor.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.medium))
                        .foregroundColor(.primary)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "arrow.up.forward.app")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var privacySafetyCard: some View {
        GlassCard(
            header: {
                SettingsSectionHeader("settings_privacy_safety_title".localized, subtitle: "settings_privacy_safety_sub".localized, iconName: "shield.fill", iconColor: .green)
            },
            content: {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(AppTransparencyFact.guarantees) { fact in
                        privacyItem(fact.icon, color: fact.color, title: fact.titleKey.localized, desc: fact.descKey.localized)
                    }
                }
            }
        )
    }

    private var knownLimitationsCard: some View {
        GlassCard(
            header: {
                SettingsSectionHeader("about_limitations_title".localized, subtitle: "about_limitations_sub".localized, iconName: "info.circle.fill", iconColor: .orange)
            },
            content: {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(AppTransparencyFact.limitations) { fact in
                        privacyItem(fact.icon, color: fact.color, title: fact.titleKey.localized, desc: fact.descKey.localized)
                    }
                }
            }
        )
    }

    private func privacyItem(_ icon: String, color: Color, title: String, desc: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(color)
                .frame(width: 18)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body.weight(.medium))
                Text(desc)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

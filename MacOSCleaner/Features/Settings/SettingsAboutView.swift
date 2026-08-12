import SwiftUI

struct SettingsAboutView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                linksCard
                privacySafetyCard
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
                    privacyItem("lock.shield.fill", color: .green, title: "settings_privacy_item_1_title".localized, desc: "settings_privacy_item_1_desc".localized)
                    privacyItem("network", color: .blue, title: "settings_privacy_item_2_title".localized, desc: "settings_privacy_item_2_desc".localized)
                    privacyItem("trash.fill", color: .teal, title: "settings_privacy_item_3_title".localized, desc: "settings_privacy_item_3_desc".localized)
                    privacyItem("checkmark.seal.fill", color: .purple, title: "settings_privacy_item_4_title".localized, desc: "settings_privacy_item_4_desc".localized)
                    privacyItem("exclamationmark.shield.fill", color: .orange, title: "settings_privacy_item_5_title".localized, desc: "settings_privacy_item_5_desc".localized)
                    privacyItem("cpu.fill", color: .pink, title: "settings_privacy_item_6_title".localized, desc: "settings_privacy_item_6_desc".localized)
                    privacyItem("hand.raised.fill", color: .yellow, title: "settings_privacy_item_7_title".localized, desc: "settings_privacy_item_7_desc".localized)
                    privacyItem("xmark.app.fill", color: .indigo, title: "settings_privacy_item_8_title".localized, desc: "settings_privacy_item_8_desc".localized)
                    privacyItem("key.fill", color: .cyan, title: "settings_privacy_item_9_title".localized, desc: "settings_privacy_item_9_desc".localized)
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

import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @State private var showTransparencySheet = false
    var availableUpdate: AvailableUpdate? = nil

    var body: some View {
        GlassEffectContainer {
            VStack(spacing: 0) {
                header
                contentStack
            }
            .frame(width: 380)
        }
        .sheet(isPresented: $showTransparencySheet) {
            AboutTransparencySheet()
        }
    }

    private var header: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .frame(width: 88, height: 88)
                .shadow(color: .accentColor.opacity(0.3), radius: 12, y: 6)

            VStack(spacing: 4) {
                Text("MacOS Cleaner")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                Text(String(format: "about_version".localized, Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "version_unknown".localized))
                    .font(.callout)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 28)
        .padding(.bottom, 20)
        .background {
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(colorScheme == .dark ? 0.25 : 0.15))
                    .blur(radius: 40)
                    .offset(y: -20)
            }
        }
    }

    private var contentStack: some View {
        VStack(spacing: 14) {
            if let update = availableUpdate {
                updateBanner(update: update)
            }

            developerCard
            linksCard

            Button {
                showTransparencySheet = true
            } label: {
                Label("about_transparency_button".localized, systemImage: "checkmark.shield")
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .frame(height: 24)
            }
            .secondaryGlassButtonStyle()

            Text("about_copyright".localized)
                .font(.caption2)
                .foregroundColor(.secondary.opacity(0.8))

            Button(action: { dismiss() }) {
                Text("close".localized)
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 28)
            }
            .glassButtonStyle()
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
        .padding(20)
    }

    private func updateBanner(update: AvailableUpdate) -> some View {
        Button {
            UpdatePromptController.open(update)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.title2)
                    .foregroundStyle(.purple)

                VStack(alignment: .leading, spacing: 2) {
                    Text(String(format: "update.available".localized, update.version))
                        .font(.headline)
                        .lineLimit(nil)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text((update.dmgURL != nil ? "update.download_dmg" : "update.download").localized + " →")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(nil)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.purple.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.purple.opacity(0.28), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func safeURL(_ string: String) -> URL {
        URL(string: string) ?? URL(fileURLWithPath: "/")
    }

    private var developerCard: some View {
        Link(destination: safeURL("https://orcid.org/0009-0002-8907-5406")) {
            HStack(spacing: 12) {
                Image(systemName: "person.circle.fill")
                    .font(.title3)
                    .foregroundColor(.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("about_developer".localized)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                    Text("about_orcid".localized)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "arrow.up.forward.app")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .glassCard(cornerRadius: 12)
        .buttonStyle(.plain)
    }

    private var linksCard: some View {
        VStack(spacing: 0) {
            Link(destination: safeURL("https://github.com/AlexTkDev/MacOSCleaner/blob/main/DONATE.md")) {
                Label("about_donate".localized, systemImage: "heart.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.pink)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .contentShape(Rectangle())
            }
            Divider().padding(.leading, 38)
            Link(destination: safeURL("https://github.com/AlexTkDev/MacOSCleaner")) {
                Label("about_star_github".localized, systemImage: "star.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.yellow)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .contentShape(Rectangle())
            }
            Divider().padding(.leading, 38)
            Link(destination: safeURL("https://alextkdev.github.io/MacOSCleaner/")) {
                Label("about_website".localized, systemImage: "globe")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .contentShape(Rectangle())
            }
            Divider().padding(.leading, 38)
            Link(destination: safeURL("https://github.com/AlexTkDev/MacOSCleaner/issues")) {
                Label("about_problem_link".localized, systemImage: "exclamationmark.bubble.fill")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .contentShape(Rectangle())
            }
            Divider().padding(.leading, 38)
            Link(destination: safeURL("https://www.linkedin.com/in/aleksandrtk/")) {
                Label("about_linkedin".localized, systemImage: "person.crop.circle.badge.plus")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .contentShape(Rectangle())
            }
        }
        .glassCard(cornerRadius: 12)
        .buttonStyle(.plain)
    }
}

private struct AboutTransparencySheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("about_transparency_button".localized)
                    .font(.headline)
                Spacer()
                Button("close".localized) { dismiss() }
                    .secondaryGlassButtonStyle()
                    .controlSize(.small)
            }
            .padding(16)

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    sectionHeader("settings_privacy_safety_title".localized)
                    ForEach(AppTransparencyFact.guarantees) { fact in
                        factRow(fact)
                    }

                    Divider()

                    sectionHeader("about_limitations_title".localized)
                    ForEach(AppTransparencyFact.limitations) { fact in
                        factRow(fact)
                    }
                }
                .padding(16)
            }
        }
        .frame(width: 480, height: 520)
    }

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.subheadline.weight(.semibold))
    }

    private func factRow(_ fact: AppTransparencyFact) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: fact.icon)
                .foregroundStyle(fact.color)
                .frame(width: 18)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(fact.titleKey.localized)
                    .font(.callout.weight(.medium))
                Text(fact.descKey.localized)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#Preview {
    AboutView(availableUpdate: AvailableUpdate(version: "3.0.0", dmgURL: nil))
}

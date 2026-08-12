import SwiftUI

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    var availableUpdate: String? = nil

    var body: some View {
        GlassEffectContainer {
            VStack(spacing: 0) {
                header
                contentStack
            }
            .frame(width: 380)
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
                updateBanner(version: update)
            }

            developerCard
            linksCard

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

    private func updateBanner(version: String) -> some View {
        Button {
            NSWorkspace.shared.open(UpdateChecker.releasesURL)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.title2)
                    .foregroundStyle(.purple)

                VStack(alignment: .leading, spacing: 2) {
                    Text(String(format: "update.available".localized, version))
                        .font(.headline)
                        .lineLimit(nil)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("update.download".localized + " →")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(nil)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .padding(12)
            .glassEffect(.regular.tint(.purple.opacity(0.2)))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }

    private var developerCard: some View {
        Link(destination: URL(string: "https://orcid.org/0009-0002-8907-5406")!) {
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
            Link(destination: URL(string: "https://github.com/AlexTkDev/MacOSCleaner")!) {
                Label("about_star_github".localized, systemImage: "star.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.yellow)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .contentShape(Rectangle())
            }
            Divider().padding(.leading, 38)
            Link(destination: URL(string: "https://alextkdev.github.io/MacOSCleaner/")!) {
                Label("about_website".localized, systemImage: "globe")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .contentShape(Rectangle())
            }
            Divider().padding(.leading, 38)
            Link(destination: URL(string: "https://github.com/AlexTkDev/MacOSCleaner/issues")!) {
                Label("about_problem_link".localized, systemImage: "exclamationmark.bubble.fill")
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .contentShape(Rectangle())
            }
            Divider().padding(.leading, 38)
            Link(destination: URL(string: "https://www.linkedin.com/in/aleksandrtk/")!) {
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

#Preview {
    AboutView(availableUpdate: "2.1.1")
}
